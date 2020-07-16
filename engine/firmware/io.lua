local loadfile = ...

local INTERVAL = 0.01 -- socket select timeout

-- C libs only
local thread = require "thread"
local lsocket = require "lsocket"
local protocol = require "protocol"
local crypt = require "crypt"
local _print

local function byte2hex(c)
	return ("%02x"):format(c:byte())
end

local function sha1(str)
	return crypt.sha1(str):gsub(".", byte2hex)
end


local config = {}
local channel = {}
local logqueue = {}
local repo = {
	repo = nil,
	uncomplete = {},
}

local connection = {
	request_path = {},	-- requesting path
	request_hash = {},	-- requesting hash
	sendq = {},
	recvq = {},
	fd = nil,
	subscibe = {},
}

local function init_channels()
	-- init channels
	channel.req = thread.channel_consume "IOreq"

	local channel_index = {}
	channel.resp = setmetatable({} , channel_index)

	function channel_index:__index(id)
		assert(type(id) == "number")
		local c = assert(thread.channel_produce("IOresp" .. id))
		self[id] = c
		return c
	end

	local channel_user = {}
	channel.user = setmetatable({} , channel_user)

	function channel_user:__index(name)
		local c = assert(thread.channel_produce(name))
		self[name] = c
		return c
	end

	local origin = os.time() - os.clock()
	local function os_date(fmt)
		local ti, tf = math.modf(origin + os.clock())
		return os.date(fmt, ti):gsub('{ms}', ('%03d'):format(math.floor(tf*1000)))
	end
	local function round(x, increment)
		increment = increment or 1
		x = x / increment
		return (x > 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)) * increment
	end
	local function packstring(...)
		local t = {}
		for i = 1, select('#', ...) do
			local x = select(i, ...)
			if math.type(x) == 'float' then
				x = round(x, 0.01)
			end
			t[#t + 1] = tostring(x)
		end
		return table.concat(t, '\t')
	end
	_print = _G.print
	function _G.print(...)
		local info = debug.getinfo(2, 'Sl')
		logqueue[#logqueue+1] = ('[%s][IO   ](%s:%3d) %s'):format(os_date('%Y-%m-%d %H:%M:%S:{ms}'), info.short_src, info.currentline, packstring(...))
	end
end

local function read_config(path, env)
	env = env or {}
	local r = loadfile(path, "t", env)
	if not r then
		return
	end
	if not pcall(r) then
		return
	end
	return env
end

local function init_config()
	local c = channel.req()
	config.repopath = assert(c.repopath)
	config.nettype = assert(c.nettype)
	config.address = assert(c.address)
	config.port = assert(c.port)
	config.vfspath = assert(c.vfspath)
	config.rootname = c.rootname
	read_config(config.repopath .. "config", config)
end

local function init_repo()
	local vfs = assert(loadfile(config.vfspath, 'engine/firmware/vfs.lua'))()
	repo.repo = vfs.new(config.repopath)
end

local function connect_server(address, port)
	print("Connecting", address, port)
	local fd, err = lsocket.connect(address, port)
	if not fd then
		print("connect:", err)
		return
	end
	local rd,wt = lsocket.select(nil, {fd})
	if not rd then
		print("select:", wt)	-- select error
		fd:close()
		return
	end
	local ok, err = fd:status()
	if not ok then
		fd:close()
		print("status:", err)
		return
	end
	print("Connected")
	return fd
end

local function listen_server(address, port)
	print("Listening", address, port)
	local fd, err = lsocket.bind(address, port)
	if not fd then
		print("bind:", err)
		return
	end
	local rd,wt = lsocket.select({fd}, 1)
	if rd == false then
		print("select:", 'timeout')
		fd:close()
		return
	elseif rd == nil then
		print("select:", wt)	-- select error
		fd:close()
		return
	end
	local newfd, err = fd:accept()
	if not newfd then
		fd:close()
		print("accept:", err)
		return
	end
	print("Accepted")
	return newfd
end

local function wait_server()
	if config.nettype == "listen" then
		return listen_server(config.address, config.port)
	end
	if config.nettype == "connect" then
		return connect_server(config.address, config.port)
	end
end

-- response io request with id
local function response_id(id, ...)
	if id then
		channel.resp[id](...)
	end
end

local function response_err(id, msg)
	print(msg)
	response_id(id, nil, msg)
end

local function logger_dispatch(t)
	for i = 1, #logqueue do
		t.SEND("LOG", logqueue[i])
		logqueue[i] = nil
	end
end

local offline = {}

function offline.LIST(id, path)
	local dir = repo.repo:list(path)
	if dir then
		local result = {}
		for k,v in pairs(dir) do
			result[k] = v.dir
		end
		response_id(id, result)
	else
		response_id(id, nil)
	end
end

function offline.TYPE(id, fullpath)
	local path, name = fullpath:match "(.*)/(.-)$"
	if path == nil then
		if fullpath == "" then
			response_id(id, "dir")
			return
		end
		path = ""
		name = fullpath
	end
	local dir, hash = repo.repo:list(path)
	if dir then
		local v = dir[name]
		if v then
			response_id(id, v.dir and "dir" or "file")
			return
		end
	end
	response_id(id, nil)
end

function offline.GET(id, fullpath)
	local path, name = fullpath:match "(.*)/(.-)$"
	if path == nil then
		path = ""
		name = fullpath
	end
	local dir = repo.repo:list(path)
	if not dir then
		response_id(id, nil)
		return
	end
	local v = dir[name]
	if not v or v.dir then
		response_id(id, nil)
		return
	end
	local realpath = repo.repo:hashpath(v.hash)
	response_id(id, realpath, v.hash)
end

function offline.EXIT(id)
	response_id(id, nil)
	error "EXIT"
end

function offline.SEND(msg, ...)
	if msg == "LOG" then
		_print(...)
	end
end

do
	local function noresponse_function() end
	offline.FETCHALL = noresponse_function
	offline.PREFETCH = noresponse_function
	offline.SUBSCIBE = noresponse_function
end

local function offline_dispatch(cmd, id, ...)
	local f = offline[cmd]
	if not f then
		print("Unsupported offline command : ", cmd, id)
	else
		f(id, ...)
	end
end

local function work_offline()
	local c = channel.req
	while true do
		offline_dispatch(c())
		logger_dispatch(offline)
	end
end

local online = {}

local function connection_send(...)
	local pack = protocol.packmessage({...})
	table.insert(connection.sendq, 1, pack)
end

-- fd set for select
local rdset = {}
local wtset = {}
local function connection_dispose(timeout)
	local sending = connection.sendq
	local fd = connection.fd
	local rd, wt
	if #sending > 0  then
		rd, wt = lsocket.select(rdset, wtset, timeout)
	else
		rd, wt = lsocket.select(rdset, timeout)
	end
	if not rd then
		if rd == false then
			-- timeout
			return false
		end
		-- select error
		return nil, wt
	end
	if wt and wt[1] then
		while true do
			local data = table.remove(sending)
			if data == nil then
				break
			end
			local nbytes, err = fd:send(data)
			if nbytes then
				if nbytes < #data then
					table.insert(sending, data:sub(nbytes+1))
					break
				end
			else
				if err then
					return nil, err
				else
					table.insert(sending, data)	-- push back
				end
				break
			end
		end
	end
	if rd[1] then
		local data, err = fd:recv()
		if not data then
			if err then
				-- socket error
				return nil, err
			end
			return nil, "Closed by remote"
		end
		table.insert(connection.recvq, data)
	end
	return true
end

local function request_file(id, hash, path, req)
	local hash_list = connection.request_hash[hash]
	if hash_list then
		hash_list[path] = true
	else
		connection.request_hash[hash] = { [path] = true }
		connection_send("GET", hash)
	end
	local path_req = connection.request_path[path]
	if not path_req then
		path_req = {}
		connection.request_path[path] = path_req
	end
	-- one request per id
	if id and path_req[id] then
		print("More than one request from id", id)
	end

	path_req[id] = req
end

-- file server update hash file
local function hash_complete(hash, exist)
	local hash_list = connection.request_hash[hash]
	if not hash_list then
		return
	end
	connection.request_hash[hash] = nil
	for path in pairs(hash_list) do
		local path_req = connection.request_path[path]
		if not path_req then
			print("No request:", path)
			return
		end
		connection.request_path[path] = nil
		if exist then
			for id, req in pairs(path_req) do
				online[req](id, path)	-- request/response path
			end
		else
			for id in pairs(path_req) do
				response_err(id, "MISSING "..path)
			end
		end
	end
end

-- response functions from file server (connection)
local response = {}

function response.ROOT(hash)
	if hash == '' then
		_print("INVALID ROOT", config.rootname)
		os.exit(-1, true)
		return
	end
	print("CHANGEROOT", hash)
	repo.repo:changeroot(hash)
end

local function writefile(filename, data)
	local temp = filename .. ".download"
	local f = io.open(temp, "wb")
	if not f then
		print("Can't write to", temp)
		return
	end
	f:write(data)
	f:close()
	if not os.rename(temp, filename) then
		os.remove(filename)
		if not os.rename(temp, filename) then
			print("Can't rename", filename)
			return false
		end
	end
	return true
end

-- REMARK: Main thread may reading the file while writing, if file server update file.
-- It's rare because the file name is sha1 of file content. We don't need update the file.
-- Client may not request the file already exist.
function response.BLOB(hash, data)
	local hashpath = repo.repo:hashpath(hash)
	if not writefile(hashpath, data) then
		return
	end
	hash_complete(hash, true)
end

function response.FILE(hash, size)
	repo.uncomplete[hash] = { size = tonumber(size), offset = 0 }
end

function response.MISSING(hash)
	print("MISSING", hash)
	hash_complete(hash, false)
end

function response.SLICE(hash, offset, data)
	offset = tonumber(offset)
	local hashpath = repo.repo:hashpath(hash)
	local tempname = hashpath .. ".download"
	local f = io.open(tempname, "ab")
	if not f then
		print("Can't write to", tempname)
		return
	end
	local pos = f:seek "end"
	if pos ~= offset then
		f:close()
		f = io.open(tempname, "r+b")
		if not f then
			print("Can't modify", tempname)
			return
		end
		f:seek("set", offset)
	end
	f:write(data)
	f:close()
	local filedesc = repo.uncomplete[hash]
	if filedesc then
		local last_offset = filedesc.offset
		if offset ~= last_offset then
			print("Invalid offset", hash, offset, last_offset)
		end
		filedesc.offset = last_offset + #data
		if filedesc.offset == filedesc.size then
			-- complete
			repo.uncomplete[hash] = nil
			if not os.rename(tempname, hashpath) then
				-- may exist
				os.remove(hashpath)
				if not os.rename(tempname, hashpath) then
					print("Can't rename", hashpath)
				end
			end
			hash_complete(hash, true)
		end
	else
		print("Offset without header", hash, offset)
	end
end

local function waiting_for_root()
	local resp = {}
	local reading = connection.recvq
	connection_send("ROOT", config.rootname)
	while true do
		local ok, err = connection_dispose(INTERVAL)
		if not ok then
			if ok == nil then
				print("dispose", err)
				return
			end
			-- timeout
		else
			local changeroot
			local result = {}
			while protocol.readmessage(reading, result) do
				if result[1] == "ROOT" then
					changeroot = result[2]
				else
					table.insert(resp, result)
					result = {}
				end
			end
			if changeroot then
				response.ROOT(changeroot)
				return resp
			end
		end
	end
end

---------- online dispatch

function online.LIST(id, path)
	local dir, hash = repo.repo:list(path)
	if dir then
		local result = {}
		for k,v in pairs(dir) do
			result[k] = v.dir
		end
		response_id(id, result)
	elseif hash then
		request_file(id, hash, path, "LIST")
	else
		print("Need Change Root", path)
		response_id(id, nil)
	end
end

local function fetch_all(path)
	local dir, hash = repo.repo:list(path)
	if dir then
		for name,v in pairs(dir) do
			local subpath = path .. "/" .. name
			if v.dir then
				fetch_all(subpath)
			else
				print("Fetch", subpath)
				online.GET(false, subpath)
			end
		end
	elseif hash then
		request_file(false, hash, path, "FETCHALL")
	else
		print("Need Change Root", path)
	end
end

function online.FETCHALL(_, path)
	fetch_all(path)
end

function online.TYPE(id, fullpath)
	local path, name = fullpath:match "(.*)/(.-)$"
	if path == nil then
		if fullpath == "" then
			response_id(id, "dir")
			return
		end
		path = ""
		name = fullpath
	end
	local dir, hash = repo.repo:list(path)
	if dir then
		local v = dir[name]
		if not v then
			response_id(id, nil)
		else
			response_id(id, v.dir and "dir" or "file")
		end
		return
	elseif hash then
		request_file(id, hash, fullpath, "TYPE")
	else
		response_id(id, nil)
	end
end

function online.GET(id, fullpath)
	local path, name = fullpath:match "(.*)/(.-)$"
	if path == nil then
		path = ""
		name = fullpath
	end
	local dir, hash = repo.repo:list(path)
	if not dir then
		if hash then
			request_file(id, hash, fullpath, "GET")
			return
		end
		response_err(id, "Not exist " .. fullpath)
		return
	end

	local v = dir[name]
	if not v or v.dir then
		response_err(id, "Not exist " .. fullpath)
		return
	end
	local realpath = repo.repo:hashpath(v.hash)
	local f = io.open(realpath,"rb")
	if not f then
		request_file(id, v.hash, fullpath, "GET")
	else
		f:close()
		response_id(id, realpath, v.hash)
	end
end

function online.PREFETCH(path)
	return online.GET(false, path)
end

function online.SUBSCIBE(channel_name, message)
	if connection.subscibe[message] then
		print("Duplicate subscibe", message, channel_name)
	end
	connection.subscibe[message] = channel_name
end

function online.SEND(...)
	connection_send(...)
end

function online.EXIT(id)
	response_id(id, nil)
	error "EXIT"
end

-- dispatch package from connection
local function dispatch_net(cmd, ...)
	local f = response[cmd]
	if not f then
		local channel_name = connection.subscibe[cmd]
		if channel_name then
			channel.user[channel_name](cmd, ...)
		else
			print("Unsupport net command", cmd)
		end
		return
	end
	f(...)
end

local function online_dispatch(ok, cmd, ...)
	if not ok then
		-- no req
		return false
	end
	local f = online[cmd]
	if not f then
		print("Unsupported online command : ", cmd)
	else
		f(...)
		--local ok, err = xpcall(f, debug.traceback, ...)
		--if not ok then
		--	print(err)
		--end
	end
	return true
end

local function work_online()
	rdset[1] = connection.fd	-- may need support multi socket
	wtset[1] = connection.fd
	local reqs = waiting_for_root()
	if not reqs then
		return
	end
	for _, req in ipairs(reqs) do
		dispatch_net(table.unpack(req))
	end
	local c = channel.req
	local result = {}
	local reading = connection.recvq
	local timeout = 0
	while true do
		while online_dispatch(c:pop(timeout)) do end
		logger_dispatch(online)
		local ok, err = connection_dispose(0)
		if ok then
			while protocol.readmessage(reading, result) do
				dispatch_net(table.unpack(result))
			end
			timeout = 0
		else
			if ok == nil then
				print("Connection Error", err)
				break
			end
			timeout = timeout + 0.001
			if timeout > INTERVAL then
				timeout = INTERVAL
			end
		end
	end
end

local function main()
	init_channels()
	init_config()
	init_repo()
	if config.address then
		connection.fd = wait_server()
		if connection.fd then
			work_online()
			-- socket error or closed
		end
	end
	local uncomplete = {}
	for hash in pairs(connection.request_hash) do
		table.insert(uncomplete, hash)
	end
	for _, hash in ipairs(uncomplete) do
		hash_complete(hash, false)
	end

	print("Working offline")
	work_offline()
end

main()
