local ecs = ...
local world = ecs.world

local fs = require 'filesystem'


ecs.import 'ant.math.adapter'
ecs.import 'ant.asset'
ecs.import 'ant.render'
ecs.import 'ant.editor'
ecs.import 'ant.inputmgr'
ecs.import 'ant.serialize'
ecs.import 'ant.scene'
ecs.import 'ant.timer'
ecs.import 'ant.bullet'
ecs.import 'ant.animation'
ecs.import 'ant.event'
ecs.import 'ant.objcontroller'
ecs.import 'ant.sky'


local serialize = import_package 'ant.serialize'

local skypkg = import_package 'ant.sky'
local skyutil = skypkg.util

local renderpkg = import_package 'ant.render'
local computil  = renderpkg.components
local camerautil= renderpkg.camera
local aniutil   = import_package 'ant.animation'.util

local mathpkg   = import_package "ant.math"
local mu        = mathpkg.util

local lu = renderpkg.light

local PVPScenLoader = require 'PVPSceneLoader'
local pbrscene = require "pbr_scene"

local init_loader = ecs.system 'init_loader'
init_loader.singleton "asyn_load_list"

init_loader.depend 'timesystem'
init_loader.depend "serialize_index_system"
init_loader.depend "procedural_sky_system"

init_loader.dependby 'render_system'
init_loader.dependby 'cull_system'
init_loader.dependby 'shadow_maker'
init_loader.dependby 'primitive_filter_system'
init_loader.dependby 'camera_controller'
init_loader.dependby 'skinning_system'
init_loader.dependby 'viewport_detect_system'
init_loader.dependby 'state_machine'

local function create_animation_test()
    local meshdir = fs.path 'meshes'
    local skepath = meshdir / 'skeleton' / 'human_skeleton.ozz'
    local anipaths = {
        meshdir / 'animation' / 'animation1.ozz',
        meshdir / 'animation' / 'animation2.ozz'
    }

    local smpath = meshdir / 'mesh.ozz'

    local anilist = {}
    for _, anipath in ipairs(anipaths) do
        anilist[#anilist + 1] = {ref_path = anipath}
    end

    local respath = fs.path '/pkg/ant.resources'

    local eid =
        world:create_entity {
        transform = {
            s = {1, 1, 1, 0},
            r = {0, 0, 0, 0},
            t = {0, 2, 0, 1}
        },
        can_render = true,
        rendermesh = {},
        material = computil.assign_material(fs.path "/pkg/ant.resources/depiction/materials/skin_model_sample.material"),
        animation = {
            pose_state = {
                pose = {
                    anirefs = {
                        {idx = 1, weight = 0.5},
                        {idx = 2, weight = 0.5}
					},
					name = "walk",
                }
            },
            anilist = {
                {
                    ref_path = respath / meshdir / 'animation' / 'animation1.ozz',
                    scale = 1,
                    looptimes = 0,
                    name = 'ani1'
                },
                {
                    ref_path = respath / meshdir / 'animation' / 'animation2.ozz',
                    scale = 1,
                    looptimes = 0,
                    name = 'ani2'
                }
            },
            blendtype = 'blend'
        },
        state_chain = {
            ref_path = fs.path "/pkg/ant.test.features" / 'assets' / 'test.sm',
        },
        skeleton = {
            ref_path = respath / skepath
        },
        skinning_mesh = {
            ref_path = respath / smpath
        },
        name = 'animation_sample',
        serialize = serialize.create(),
        collider_tag = "capsule_collider",
        capsule_collider = {
            collider = {
                center = {0, 0, 0},
                is_tigger = true,
            },
            shape = {
                radius = 1.0,
                height = 1.0,
                axis   = "Y",
            },
        },
        -- character = {
        --     movespeed = 1.0,
        -- }
    }

    -- local e = world[eid]
    -- local anicomp = e.animation
    -- aniutil.play_animation(e.animation, anicomp.pose_state.pose)
end

local function test_serialize(delfile_aftertest)
	--local eid = world:first_entity_id "main_queue"
	--local watch = import_package "ant.serialize".watch
	--local res1 = watch.query(world, nil, eid.."/camera")
	--local res2 = watch.query(world, res1.__id, "")
	--watch.set(world, res1.__id, "", "type", "test")
	--local res3 = watch.query(world, res1.__id, "")
    
    local function save_file(file, data)
        assert(assert(io.open(file, 'w')):write(data)):close()
    end
    -- test serialize world
    local s = serialize.save_world(world)
    save_file('serialize_world.txt', s)
    for _, eid in world:each 'serialize' do
        world:remove_entity(eid)
    end
    world:update_func "delete"()
    world:clear_removed()
    serialize.load_world(world, s)
    -- DO NOT call update_func "init", if you donot close the world
    -- in this test, just call "post_init" is enougth
    world:update_func "post_init"()

    --test serialize entity
    local eid = world:first_entity_id 'serialize'
    local s = serialize.save_entity(world, eid)
    save_file('serialize_entity.txt', s)
    world:remove_entity(eid)
    serialize.load_entity(world, s)

    if delfile_aftertest then
        local lfs = require "filesystem.local"
        lfs.remove(lfs.path 'serialize_world.txt')
        lfs.remove(lfs.path 'serialize_entity.txt')
    end
end

local function pbr_test()
    world:create_entity {
        transform = mu.srt(nil, nil, {3, 2, 0, 1}),
        rendermesh = {},
        mesh = {
            ref_path = fs.path "/pkg/ant.test.features/assets/DamagedHelmet.mesh",
        },
        material = {
            {
                ref_path = fs.path "/pkg/ant.test.features/assets/DamagedHelmet.pbrm",
            }
        },
        can_render = true,
        can_cast = true,
    }
end

local function create_plane_test()
    local planeeid = computil.create_plane_entity(world,
    {50, 1, 50, 0}, nil,
    fs.path "/pkg/ant.resources/depiction/materials/test/mesh_shadow.material",
    {0.8, 0.8, 0.8, 1},
    "test shadow plane")

    world:add_component(planeeid, "collider_tag", "box_collider")
    world:add_component(planeeid, "box_collider", {
        collider = {
            center = {0, 0, 0},
        },
        shape = {
            size = {50, 1, 50},
        }
    })
end

function init_loader:init()
    do
        lu.create_directional_light_entity(world, "direction light", 
		{1,1,1,1}, 2, mu.to_radian{60, 50, 0})
        lu.create_ambient_light_entity(world, 'ambient_light', 'gradient', {1, 1, 1, 1})
    end

    skyutil.create_procedural_sky(world, {follow_by_directional_light=false})

    --computil.create_grid_entity(world, 'grid', 64, 64, 1, mu.translate_mat {0, 0, 0})
    create_plane_test()

    create_animation_test()
    pbr_test()
    pbrscene.create_scene(world)
end


function init_loader:post_init()
    do
        local viewcamera = camerautil.get_camera(world, "main_view")
        viewcamera.frustum.f = 300
    end
end

function init_loader:asset_loaded()
    -- local ll = self.asyn_load_list
    -- -- scene finish
    -- if ll.i >= ll.n then
    --     if  not __ANT_RUNTIME__ and 
    --         not _RUN_TEST_SERIALIZE_ then
    --         test_serialize(true)
    --         _RUN_TEST_SERIALIZE_ = true
    --     end
    -- end
end
