local lfs = require "filesystem.local"
local async = require "async"
local loaders = {}

loaders["ozz-animation"] = function (fn)
	local animodule = require "hierarchy".animation
	local handle = animodule.new_animation(fn)
	local scale = 1     -- TODO
	local looptimes = 0 -- TODO
	return {
		_handle = handle,
		_sampling_context = animodule.new_sampling_context(),
		_duration = handle:duration() * 1000. / scale,
		_max_ratio = looptimes > 0 and looptimes or math.maxinteger,
	}
end

loaders["ozz-raw_skeleton"] = function (fn)
	local hiemodule = require "hierarchy".skeleton
	local handle = hiemodule.new()
	handle:load(fn)
	return {
		_handle = handle
	}
end

loaders["ozz-skeleton"] = function(fn)
	local hiemodule = require "hierarchy".skeleton
	local handle = hiemodule.build(fn)
	return {
		_handle = handle
	}
end

local function find_loader(localfilepath)
	local f <close> = assert(io.open(localfilepath, "rb"))
	f:seek("set", 1)
	local tag = ("z"):unpack(f:read(16))
	return loaders[tag]
end

local function loader(filename)
	local localfilename = async.compile(filename)
	local fn = find_loader(localfilename)
	if not fn then
		error "not support type"
		return
	end
	return fn(localfilename)
end

local function unloader()
end

return {
    loader = loader,
    unloader = unloader,
}
