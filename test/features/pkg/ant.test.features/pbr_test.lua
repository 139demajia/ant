local ecs = ...
local world = ecs.world
local fs = require "filesystem"


local pbr_test_sys = ecs.system "pbr_test_system"

local feature_path = fs.path "/pkg/ant.test.features"
local imaterial = ecs.require "ant.asset|material"
local math3d    = require "math3d"

local function create_pbr_entity(name, srt, material,
    color, metallic, roughness)

    local eid = world:deprecated_create_entity {
        policy = {
            "ant.render|render",
            "ant.general|name",
        },
        data = {
            name        = name,
            transform   = srt,
            material    = material,
            visible_state= "main_view|selectable",
            mesh        = "/pkg/ant.resources.binary/meshes/base/sphere.glb|meshes/Sphere_P1.meshbin",
            scene_entity = true,
        },
    }

    imaterial.set_property(eid, "u_basecolor_factor",           color)
    imaterial.set_property(eid, "u_pbr_factor",  math3d.vector(metallic, roughness, 0.0, 0.0))
    return eid
end

local function pbr_spheres()
    local num_samples = 4
    local metallic_step = 1.0 / num_samples
    local roughness_step = 1.0 / num_samples
    local basecolor = {0.8, 0.2, 0.2, 1.0}
    local movestep = 2
    local x = 0.0

    local material = (feature_path / "assets/pbr_test.material"):string()
    for row=1, num_samples do
        local metallic = row * metallic_step
        local z = 0.0
        for col=1, num_samples do
            local roughness = col * roughness_step
            create_pbr_entity("sphere" .. row .. "x" .. col, 
            {s = 100, t = {x, 0.0, z, 1.0}}, 
            material, basecolor, metallic, roughness)

            z = z + movestep
        end
        x = x + movestep
    end
end

function pbr_test_sys:init()
    ecs.create_instance("/pkg/ant.resources.binary/meshes/DamagedHelmet.glb|mesh.prefab", {})
    pbr_spheres()
end