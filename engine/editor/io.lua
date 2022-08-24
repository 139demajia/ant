local cpath, repopath = ...

package.path = "engine/?.lua"
package.cpath = cpath

local function loadfile(path)
	local f = io.open(path)
	if not f then
		return nil, path..':No such file or directory.'
	end
	local str = f:read 'a'
	f:close()
	return load(str, "@" .. path)
end

local function dofile(path)
	return assert(loadfile(path))()
end

local lfs = require "bee.filesystem"
local access = dofile "engine/vfs/repoaccess.lua"
local thread = require "bee.thread"
dofile "engine/common/log.lua"

thread.setname "ant - IO thread"

local channel = thread.channel "IOreq"
local repo

local function init_repo()
    local path = lfs.path(repopath)
    if not lfs.is_directory(path) then
       error "Not a dir"
    end
    repo = {
        _root = path,
    }
    access.readmount(repo)
end

local function response_id(id, ...)
	if id then
		if type(id) == "string" then
			local c = thread.channel(id)
			c:push(...)
		else
			channel:ret(id, ...)
		end
	end
end

local CMD = {}

function CMD.GET(path)
	local rp = access.realpath(repo, path)
	if rp and lfs.exists(rp) then
		return rp:string()
	end
end

function CMD.LIST(path)
	local item = {}
	for _, filename in ipairs(access.list_files(repo, path)) do
		local realpath = access.realpath(repo, path .. filename)
		if realpath then
			item[filename] = not not lfs.is_directory(realpath)
		end
	end
	return item
end

local function is_resource(path)
	local ext = path:extension():string():sub(2):lower()
	if ext ~= "sc" and ext ~= "glb"  and ext ~= "texture" and ext ~= "png" then
		return false
	end
	return true
end

function CMD.TYPE(path)
	local rp = access.realpath(repo, path)
	if lfs.is_directory(rp) then
		return "dir"
	elseif is_resource(rp) then
		return "resource"
	elseif lfs.is_regular_file(rp) then
		return "file"
	end
end

function CMD.FETCH(path)
end

function CMD.REPOPATH()
	return repopath
end

function CMD.MOUNT(name, path)
	access.addmount(repo, name, lfs.path(path))
end

local function dispatch(id, cmd, ...)
    local f = CMD[cmd]
    if not f then
        print("Unsupported command : ", cmd)
        response_id(id)
    else
        response_id(id, f(...))
    end
    return true
end

local function work()
	local c = channel
	while true do
		while dispatch(c:bpop()) do end
	end
end

init_repo()
work()
