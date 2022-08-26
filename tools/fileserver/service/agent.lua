local ltask = require "ltask"
local socket = require "socket"
local protocol = require "protocol"
local fs = require "bee.filesystem"

local arg = ltask.call(ltask.queryservice "arguments", "QUERY")
local FD = ...
local REPOPATH = arg[1]

local message = {}
local ServiceCompile
local ServiceDebugProxy
local ServiceVfsMgr = ltask.uniqueservice "vfsmgr"
local VfsSessionId

local ServiceLogManager = ltask.uniqueservice "log.manager"
local ServiceEditor = ltask.uniqueservice "editor"
local LoggerIndex
local LoggerFile
local LoggerQueue = {}

local function compile_resource(path)
	if not ServiceCompile then
		ServiceCompile = ltask.spawn("compile", REPOPATH)
	end
	return pcall(ltask.call, ServiceCompile, "COMPILE", path)
end

local function response(...)
	socket.send(FD, protocol.packmessage({...}))
end

local function logger_init()
	LoggerIndex, LoggerFile = ltask.call(ServiceLogManager, "CREATE", REPOPATH)
	ltask.fork(function ()
		while LoggerIndex do
			if #LoggerQueue > 0 then
				local fp <close> = assert(io.open(LoggerFile, 'a'))
				for i = 1, #LoggerQueue do
					local data = LoggerQueue[i]
					LoggerQueue[i] = nil
					fp:write(data)
					fp:write('\n')
				end
			end
			ltask.sleep(1)
		end
	end)
end

local function logger_write(data)
	ltask.send(ServiceEditor, "MESSAGE", "LOG", "RUNTIME", data)
    LoggerQueue[#LoggerQueue+1] = data
end

local function logger_quit()
	if LoggerIndex then
		ltask.call(ServiceLogManager, "CLOSE", REPOPATH, LoggerIndex)
		LoggerIndex = nil
		LoggerFile = nil
	end
end

function message.ROOT(path)
	REPOPATH = assert(REPOPATH or path, "Need repo name")
	print("ROOT", REPOPATH)
	if VfsSessionId then
		ltask.send(ServiceVfsMgr, "CLOSE", VfsSessionId)
		VfsSessionId = nil
	else
		logger_init()
	end
	local sid, roothash = ltask.call(ServiceVfsMgr, "ROOT", REPOPATH)
	VfsSessionId = sid
	response("ROOT", roothash)
end

function message.RESOURCE(path)
	local ok, lpath = compile_resource(path)
	if not ok then
		print(table.concat(lpath, "\n"))
		response("MISSING", path)
		return
	end
	local rpath = fs.relative(fs.path(lpath), fs.path(REPOPATH)):string()
	local hash = ltask.call(ServiceVfsMgr, "BUILD", VfsSessionId, "/"..rpath, lpath)
	response("RESOURCE", path, hash)
end

function message.GET(hash)
	local filename = ltask.call(ServiceVfsMgr, "GET", VfsSessionId, hash)
	if filename == nil then
		response("MISSING", hash)
		return
	end
	local f = io.open(filename, "rb")
	if not f then
		response("MISSING", hash)
		return
	end
	local sz = f:seek "end"
	f:seek("set", 0)
	if sz < 0x10000 then
		response("BLOB", hash, f:read "a")
	else
		response("FILE", hash, tostring(sz))
		local offset = 0
		while true do
			local data = f:read(0x8000)
			response("SLICE", hash, tostring(offset), data)
			offset = offset + #data
			if offset >= sz then
				break
			end
		end
	end
	f:close()
end

function message.FETCH(path)
	local hashs = ltask.call(ServiceVfsMgr, "FETCH", VfsSessionId, path)
	if not hashs then
		response("MISSING", path)
		return
	end
	response("FETCH", path, hashs)
end

function message.DBG(data)
	--if not ServiceDebugProxy then
	--	ServiceDebugProxy = ltask.spawn("debug.proxy", FD, VfsSessionId)
	--end
	--ltask.send(ServiceDebugProxy, "MESSAGE", data)
end

function message.LOG(data)
	logger_write(data)
end

function message.MSG(CMD,...)
end

local function dispatch(fd)
	local reading_queue = {}
	local output = {}
	while true do
		local reading = socket.recv(fd)
		if reading == nil then
			break
		end
		table.insert(reading_queue, reading)
		while true do
			local msg = protocol.readmessage(reading_queue, output)
			if msg == nil then
				break
			end
			local f = message[msg[1]]
			if f then
				f(table.unpack(msg, 2))
			else
				error(msg[1])
			end
		end
	end
end

local function quit()
	if VfsSessionId then
		ltask.send(ServiceVfsMgr, "CLOSE", VfsSessionId)
	end
	if ServiceCompile then
		ltask.send(ServiceCompile, "QUIT")
	end
	logger_quit()
	if ServiceDebugProxy then
		ltask.send(ServiceDebugProxy, "QUIT")
	end
end

ltask.fork(function()
	dispatch(FD)
	quit()
	ltask.quit()
end)

return {}
