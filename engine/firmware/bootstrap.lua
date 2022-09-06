__ANT_RUNTIME__ = "0.0.1"

local platform = require "platform"

local function is_ios()
	return "ios" == platform.OS:lower()
end

local needcleanup, type, address

if is_ios() then
	local clean_up_next_time = platform.setting("clean_up_next_time")
	if clean_up_next_time == true then
		platform.setting("clean_up_next_time", false)
		needcleanup = true
	end
	type = platform.setting "server_type"
	address = platform.setting "server_address"
end

do
	local fs = require "bee.filesystem"
	local appdata = fs.appdata_path()
	local root = is_ios() and appdata or appdata / "ant" / "runtime"
	local repo = root / ".repo"
	if needcleanup then
		fs.remove_all(repo)
	end
	fs.create_directories(repo)
	for i = 0, 255 do
		fs.create_directory(root / ".repo" / ("%02x"):format(i))
	end
	fs.current_path(root)
end

local config = {
	repopath = "./",
	vfspath = "vfs.lua",
	socket = nil,
	nettype = nil,
	address = nil,
	port = nil,
}

if type == nil then
	if is_ios() then
		type = "usb"
	else
		type = "remote"
		address = "127.0.0.1:2018"
	end
end

if type == "usb" then
	config.nettype = "listen"
	config.address = "127.0.0.1"
	config.port = 2018
elseif type == "remote" then
	config.nettype = "connect"
	local ip, port = address:match "^([^:]+):(%d+)"
	if ip and port then
		config.address = ip
		config.port = port
	else
		config.address = "127.0.0.1"
		config.port = '2018'
	end
elseif type == "offline" then
end

local fw = require "firmware"
local socket = require "bee.socket"
local host = {}
local bootloader
local first = true
local quit
function host.update(apis)
	if first then
		first = false
		apis.request("FETCH", "/engine", {
			resolve = function ()
				quit = true
			end,
			reject = function (_, errmsg)
				error(errmsg)
			end,
		})
	end
	if quit then
		return true
	end
end
function host.exit(apis)
	if apis.fd then
		if config.nettype == "listen" then
			config.socket = socket.dump(apis.fd)
		else
			apis.fd:close()
		end
	end
	bootloader = assert(apis.repo:realpath '/engine/firmware/bootloader.lua')
end
assert(fw.loadfile "io.lua")(fw.loadfile, config, host)

local function loadfile(path, name)
	local f = io.open(path)
	if not f then
		return nil, ('%s:No such file or directory.'):format(name)
	end
	local str = f:read 'a'
	f:close()
	return load(str, "@/" .. name)
end
assert(loadfile(bootloader, '/engine/firmware/bootloader.lua'))(config)
