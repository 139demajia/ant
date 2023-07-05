local serialize = import_package "ant.serialize"
local fs = require "filesystem.local"
local utility = require "editor.model.utility"
local datalist = require "datalist"
local texture_compile = require "editor.texture.compile"
local parallel_task   = require "editor.parallel_task"

local image_extension = {
    ["image/jpeg"] = ".jpg",
    ["image/png"] = ".png",
    ["image/bmp"] = ".bmp",
}

local function tov4(v, def)
    if v == nil then
        return def
    end
    if #v == 4 then
        return v
    end
    if #v < 4 then
        local vv = {0, 0, 0, 0}
        for i=1, #v do
            vv[i] = v[i]
        end
        return vv
    end
    return {v[1], v[2], v[3], v[4]}
end

local default_pbr_param = {
    basecolor = {
        texture = "/pkg/ant.resources/textures/pbr/default/basecolor.texture",
        factor = {1, 1, 1, 1},
        stage = 0,
    },
    metallic_roughness = {
        texture = "/pkg/ant.resources/textures/pbr/default/metallic_roughness.texture",
        factor = {1, 0, 0, 0},
        stage = 1,
    },
    normal = {
        texture = "/pkg/ant.resources/textures/pbr/default/normal.texture",
        stage = 2,
    },
    emissive = {
        texture = "/pkg/ant.resources/textures/pbr/default/emissive.texture",
        factor = {0, 0, 0, 0},
        stage = 3,
    },
    occlusion = {
        texture = "/pkg/ant.resources/textures/pbr/default/occlusion.texture",
        stage = 4,
    }
}

local filter_tags = {
    NEAREST = 9728,
    LINEAR = 9729,
    NEAREST_MIPMAP_NEAREST = 9984,
    LINEAR_MIPMAP_NEAREST = 9985,
    NEAREST_MIPMAP_LINEAR = 9986,
    LINEAR_MIPMAP_LINEAR = 9987,
}

local filter_names = {}
for k, v in pairs(filter_tags) do
    assert(filter_names[v] == nil, "duplicate value")
    filter_names[v] = k
end

local address_tags = {
    CLAMP_TO_EDGE   = 33071,
    MIRRORED_REPEAT = 33648,
    REPEAT          = 10497,
}

local address_names = {}
for k, v in pairs(address_tags) do
    assert(address_names[v] == nil)
    address_names[v] = k
end

local default_sampler_flags = {
    maxFilter   = filter_tags["LINEAR"],
    minFilter   = filter_tags["LINEAR"],
    wrapS       = address_tags["REPEAT"],
    wrapT       = address_tags["REPEAT"],
}

local MIP_map = {
    NEAREST = "POINT",
    LINEAR = "POINT",
    NEAREST_MIPMAP_NEAREST = "POINT",
    LINEAR_MIPMAP_NEAREST = "POINT",
    NEAREST_MIPMAP_LINEAR = "LINEAR",
    LINEAR_MIPMAP_LINEAR = "LINEAR",
}

local MAG_MIN_map = {
    NEAREST = "POINT",
    LINEAR = "LINEAR",
    NEAREST_MIPMAP_NEAREST = "POINT",
    LINEAR_MIPMAP_NEAREST = "POINT",
    NEAREST_MIPMAP_LINEAR = "LINEAR",
    LINEAR_MIPMAP_LINEAR = "LINEAR",
}

local UV_map = {
    CLAMP_TO_EDGE   = "CLAMP",
    MIRRORED_REPEAT = "MIRROR",
    REPEAT          = "WRAP",
}


local function get_default_code(stage)
    if stage == 'vs' then return "common/default_vs_func.sh"
    elseif stage == 'fs' then return "common/default_fs_func.sh"
    end
end

local function get_default_fx()
    return {
        shader_type = "PBR",
        fs = "/pkg/ant.resources/shaders/dynamic_material/fs_default.sc",
        vs = "/pkg/ant.resources/shaders/dynamic_material/vs_default.sc",
        vs_code     = get_default_code('vs'),
        fs_code     = get_default_code('fs'),
    }
end

local states = {}

local function read_datalist(statefile)
    local s = states[statefile]
    if s == nil then
        local f = fs.open(statefile)
        local c = f:read "a"
        f:close()
        s = datalist.parse(c)
    end

    return s
end

local function save_texture(saved_files, output, exports, texture_desc)
    if not saved_files[output:string()] then
        saved_files[output:string()] = true
        parallel_task.add(exports.tasks, function ()
            local ok, err = texture_compile(texture_desc, output, function (path)
                path = path[1]
                if path:sub(1,1) == "/" then
                    return fs.path(path):localpath()
                end
                return fs.absolute(output:parent_path() / (path:match "^%./(.+)$" or path))
            end)
            if not ok then
                error("compile failed: " .. output:string() .. "\n" .. err)
            end
        end)
    end
end

return function (output, glbdata, exports, tolocalpath)
    local glbscene, glbbin = glbdata.info, glbdata.bin
    local materials = glbscene.materials

    local saved_files = {}

    if not materials then
        return
    end

    local images = glbscene.images
    local bufferviews = glbscene.bufferViews
    local buffers = glbscene.buffers
    local textures = glbscene.textures
    local samplers = glbscene.samplers
    local function export_image(imgidx)
        local img = images[imgidx+1]
        local ext = image_extension[img.mimeType]
        if ext == nil then
            if img.uri then
                error("not support base64 format")
            end
            error(("not support image type:%d"):format(img.mimeType))
        end

        local name = img.name or tostring(imgidx)
        if fs.path(name):extension():string() ~= ext then
            name = name .. ext
        end

        local outfile = output / "images" / name
        if not saved_files[outfile:string()] then
            local bv = bufferviews[img.bufferView+1]
            local buf = buffers[bv.buffer+1]
            local begidx = (bv.byteOffset or 0)+1
            local endidx = begidx + bv.byteLength
            assert((endidx - 1) <= buf.byteLength)
            local c = glbbin:sub(begidx, endidx)
            utility.save_file("./images/"..name, c)

            saved_files[outfile:string()] = true
        end
        return name
    end

    local function to_sampler(sampleidx)
        local gltfsampler = sampleidx and samplers[sampleidx + 1] or default_sampler_flags
    
        local minfilter = gltfsampler.minFilter or default_sampler_flags.minFilter
        local maxFilter = gltfsampler.maxFilter or default_sampler_flags.maxFilter
        
        local wrapS, wrapT =    
            gltfsampler.wrapS or default_sampler_flags.wrapS,
            gltfsampler.wrapT or default_sampler_flags.wrapT
    
        return {
            MIP = MIP_map[filter_names[minfilter]],
            MIN = MAG_MIN_map[filter_names[minfilter]],
            MAG = MAG_MIN_map[filter_names[maxFilter]],
            U = UV_map[address_names[wrapS]],
            V = UV_map[address_names[wrapT]],
        }
    end

    local function add_texture_format(texture_desc, need_compress)
        if need_compress then
            texture_desc.compress = {
                    android = "ASTC6x6",
                    ios = "ASTC6x6",
                    windows = texture_desc.normalmap and "BC5" or "BC3",
                }
        else
            texture_desc.format = "RGBA8"
        end
    end

    local function fetch_texture_info(texidx, normalmap, colorspace)
        local tex = textures[texidx+1]
        local imgname = export_image(tex.source)
        local texture_desc = {
            path = serialize.path("./"..imgname),
            sampler = to_sampler(tex.sampler),
            normalmap = normalmap,
            colorspace = colorspace,
            type = "texture",
        }

        --TODO: check texture if need compress
        local need_compress<const> = true
        add_texture_format(texture_desc, need_compress)
        local imgname_noext = fs.path(imgname):stem():string()
        local texname = imgname_noext .. ".texture"
        local texfilename = "./images/" .. texname
        local outtexfile = output / texfilename
        save_texture(saved_files, outtexfile, exports, texture_desc)

        --we need output texture path which is relate to *.material file, so we need ..
        return serialize.path("./../images/" .. texname)
    end

    local function handle_texture(tex_desc, name, normalmap, colorspace)
        if tex_desc then
            local filename = fetch_texture_info(tex_desc.index, normalmap, colorspace)
            return {
                texture = filename,
                stage = default_pbr_param[name].stage,
            }
        end
    end

    local function get_state(isopaque)
        local name = isopaque and 
            "/pkg/ant.resources/materials/states/default.state" or
            "/pkg/ant.resources/materials/states/translucent.state"
        return read_datalist(tolocalpath(name))
    end


    exports.material = {}
    for matidx, mat in ipairs(materials) do
        local name = mat.name or tostring(matidx)
        local pbr_mr = mat.pbrMetallicRoughness

        local isopaque = mat.alphaMode == nil or mat.alphaMode == "OPAQUE"
        local material = {
            fx          = get_default_fx(),
            state       = get_state(isopaque),
            properties  = {
                s_basecolor          = handle_texture(pbr_mr.baseColorTexture, "basecolor", false, "sRGB"),
                s_metallic_roughness = handle_texture(pbr_mr.metallicRoughnessTexture, "metallic_roughness", false, "linear"),
                s_normal             = handle_texture(mat.normalTexture, "normal", true, "linear"),
                s_emissive           = handle_texture(mat.emissiveTexture, "emissive", false, "sRGB"),
                s_occlusion          = handle_texture(mat.occlusionTexture, "occlusion", false, "linear"),
                u_basecolor_factor   = tov4(pbr_mr.baseColorFactor, default_pbr_param.basecolor.factor),
                u_emissive_factor    = tov4(mat.emissiveFactor, default_pbr_param.emissive.factor),
                u_pbr_factor         = {
                    pbr_mr.metallicFactor or 1.0,
                    pbr_mr.roughnessFactor or 1.0,
                    mat.alphaCutoff or 0.5,
                    1.0, --occlusion strength
                },
            },
        }

        local setting = {}
        if isopaque then
            setting["ALPHAMODE_OPAQUE"] = 1
        else
            setting["MATERIAL_UNLIT"] = 1
        end
        if mat.alphaCutoff then
            setting["ALPHAMODE_MASK"] = 1
        end

        if mat.doubleSided then
            --default is CCW
            material.state.CULL = "NONE"
        end

        material.fx.setting = setting
        local function refine_name(name)
            local newname = name:gsub("['\\/:*?\"<>|]", "_")
            return newname
        end
        local materialname = refine_name(name)
        exports.material[matidx] = {
            filename = fs.path "./materials/" .. materialname .. ".material",
            material = material,
        }
    end
end
