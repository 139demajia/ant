local ecs = ...
local world = ecs.world

local serialize = import_package "ant.serialize"
local fs = require "filesystem"

local mathpkg   = import_package "ant.math"
local mu        = mathpkg.util
local math3d    = require "math3d"

local renderpkg = import_package "ant.render"
local computil  = renderpkg.components

local iktest_sys = ecs.system "character_ik_test"
iktest_sys.require_policy "ant.character|foot_ik_raycast"

local function foot_ik_test()

    local assetpath = fs.path '/pkg/ant.resources.binary/meshes/ozz'
    return world:create_entity {
        policy = {
            "ant.serialize|serialize",
            "ant.render|render",
            "ant.animation|animation",
            "ant.animation|animation_controller.birth",
            "ant.animation|ozzmesh",
            "ant.animation|ik",
            "ant.animation|ozz_skinning",
            "ant.render|shadow_cast",
            "ant.render|name",
            "ant.character|character",
            "ant.character|foot_ik_raycast",
        },
        data = {
            transform = {srt = {t= {-2.5, 0, -6, 1}}},
            rendermesh = {},
            material = "/pkg/ant.resources/depiction/materials/skin_model_sample.material",
            mesh = '/pkg/ant.resources.binary/meshes/ozz/mesh.ozz',
            skeleton = '/pkg/ant.resources.binary/meshes/ozz/human_skeleton.ozz',
            animation = {
                anilist = {
                    idle = {
                        resource = '/pkg/ant.test.features/assets/tmp/animation.ozz',
                        scale = 1,
                        looptimes = 0,
                    },
                },
            },
            animation_birth = "idle",
            ik = {
                jobs = {
                    left_leg = {
                        type        = "two_bone",
                        target      = {0, 0, 0, 1},
                        pole_vector = {0, 1, 0, 0},
                        mid_axis    = {0, 0, 1, 0},
                        weight      = 1.0,
                        twist_angle = 0,
                        soften      = 1.0,
                        joints      = {"LeftUpLeg", "LeftLeg", "LeftFoot",},
                    },
                    left_sole = {
                        type        = "aim",
                        target      = {0, 0, 0, 1},
                        pole_vector = {0, 1, 0, 0},
                        up_axis     = {0, 1, 0, 0},
                        forward     = {-1, 0, 0, 0},
                        offset      = {0, 0, 0, 0},
                        weight      = 1.0,
                        twist_angle = 0,
                        joints      = {"LeftFoot",}
                    },
                    right_leg = {
                        type        = "two_bone",
                        target      = {0, 0, 0, 1},
                        pole_vector = {0, 1, 0, 0},
                        mid_axis    = {0, 0, 1, 0},
                        weight      = 1.0,
                        twist_angle = 0,
                        soften      = 1.0,
                        joints      = {"RightUpLeg", "RightLeg", "RightFoot",},
                    },
                    right_sole = {
                        type        = "aim",
                        target      = {0, 0, 0, 1},
                        pole_vector = {0, 1, 0, 0},
                        up_axis     = {0, 1, 0, 0},
                        forward     = {-1, 0, 0, 0},
                        offset      = {0, 0, 0, 0},
                        weight      = 1.0,
                        twist_angle = 0,
                        joints      = {"RightFoot",}
                    },
                }
            },
            foot_ik_raycast = {
                cast_dir = {0, -2, 0, 0},
                foot_height = 0.5,
                trackers = {
                    {
                        leg = "left_leg",
                        sole = "left_sole",
                    },
                    {
                        leg = "right_leg",
                        sole = "right_sole",
                    },
                },
            },
            character = {movespeed = 1.0,},
            collider = {
                capsule = {
                    {
                        origin = {0, 1, 0, 1},
                        radius = 0.5,
                        height = 1,
                        axis = "Y",
                    }
                }
            },
            serialize = serialize.create(),
            name = "foot_ik_test",
            can_cast = true,
            can_render = true,
            scene_entity = true,
        }
    }
    
end

local function create_plane_test()
    return computil.create_plane_entity(world,
    {srt = {
        s = {5, 1, 5, 0},
        r = math3d.totable(math3d.quaternion{math.rad(10), 0, 0}),
        t = {0, 0, -5, 1},
    }},
    "/pkg/ant.resources/depiction/materials/test/singlecolor_tri_strip.material",
    {0.5, 0.5, 0, 1},
    "test shadow plane",
    {
        ["ant.collision|collider"] = {
            collider = {
                box = {
                    {
                        origin = {0, 0, 0, 1},
                        size = {5, 0.001, 5},
                    }
                }
            },
        },
        ["ant.render|debug_mesh_bounding"] = {
            debug_mesh_bounding = true,
        }
    })
end

function iktest_sys:init()
    local eid = create_plane_test()
    local e = world[eid]
    local p = e.material.properties
    local c = p.uniforms.u_color.value
    local tt = math3d.totable(c)
    print(tt)
    --foot_ik_test()
end