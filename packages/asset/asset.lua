local cr = import_package "ant.compile_resource"
local setting = import_package "ant.settings".setting
local resource = require "resource"
local url = import_package "ant.url"
local texture_mgr = require "texture_mgr"

local assetmgr = {}

local CURPATH = {}
local function push_currentpath(path)
	CURPATH[#CURPATH+1] = path:match "^(.-)[^/|]*$"
end
local function pop_currentpath()
	CURPATH[#CURPATH] = nil
end
local function absolute_path(path)
	local base = CURPATH[#CURPATH]
	if path:sub(1,1) == "/" or not base then
		return path
	end
	return base .. (path:match "^%./(.+)$" or path)
end

local function require_ext(ext)
	return require("ext_" .. ext)
end

local function initialize()
	local function loader(fileurl, data)
		local filename = url.parse(fileurl)
		local ext = filename:match "[^.]*$"
		local world = data
		local res
		push_currentpath(filename)
		res = require_ext(ext).loader(fileurl, world)
		pop_currentpath()
		return res
	end
	local function unloader(filename, data, res)
		local ext = filename:match "[^.]*$"
		local world = data
		require_ext(ext).unloader(res, world)
	end
	resource.register(loader, unloader)
end

function assetmgr.resource(path, world)
	local fullpath = absolute_path(path)
	resource.load(fullpath, world, true)
	return resource.proxy(fullpath)
end

local curve_world = setting:data().graphic.curve_world
local enable_bloom = setting:get "graphic/postprocess/bloom/enable"
local curve_world_type_macros<const> = {
    view_sphere = 1,
    cylinder = 2,
}

local default_setting = {}

if curve_world.enable then
	default_setting["ENABLE_CURVE_WORLD"] = curve_world_type_macros[curve_world.type]
end

if enable_bloom then
	default_setting["BLOOM_ENABLE"] = 1
end


local function merge(a, b)
	for k, v in pairs(default_setting) do
		if not a[k] then
			a[k] = v
		end
	end
    for k, v in pairs(b) do
        if not a[k] then
            a[k] = v
        end
    end
end

function assetmgr.load_fx(fx, setting)
	setting = setting or {}
	local newfx = { setting = setting }
	local function check_resolve_path(p)
		if fx[p] then
			newfx[p] = absolute_path(fx[p])
		end
	end
	check_resolve_path "varying_path"
	check_resolve_path "vs"
	check_resolve_path "fs"
	check_resolve_path "cs"
    if fx.setting then
        merge(setting, fx.setting)
    end
	return cr.load_fx(newfx)
end

function assetmgr.init()
	texture_mgr.init()
	initialize()
end

assetmgr.edit = resource.edit
assetmgr.unload = resource.unload
assetmgr.reload = resource.reload
assetmgr.textures = texture_mgr.textures

return assetmgr
