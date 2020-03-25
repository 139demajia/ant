local lfs 	= require "filesystem.local"
local config= require "mesh.default_cfg"
local glb_cvt= require "mesh.glb_convertor"
local util 	= require "util"

local utilitypkg = import_package "ant.utility.local"
local fs_util = utilitypkg.fs_util

return function (identity, sourcefile, outfile, localpath)
	local meshcontent = util.rawtable(sourcefile)
	local meshpath = localpath(meshcontent.mesh_path)

	glb_cvt(meshpath:string(), outfile:string(), meshcontent.config or config)

	if lfs.exists(outfile) then
		util.embed_file(outfile, meshcontent, {fs_util.fetch_file_content(outfile)})
		return true, ""
	end

	return false, "convert file failed:" .. meshpath:string()
end
