local ecs   = ...
local world = ecs.world
local w     = world.w

local math3d    = require "math3d"
local bgfx      = require "bgfx"

local irender   = ecs.require "ant.render|render_system.render"
local iom       = ecs.require "ant.objcontroller|obj_motion"

local mathpkg   = import_package "ant.math"
local mu, mc    = mathpkg.util, mathpkg.constant

local renderpkg = import_package "ant.render"
local layoutmgr = renderpkg.layoutmgr
local S         = ecs.system "init_system"

local function create_instance(prefab, on_ready)
    local p = world:create_instance {
        prefab = prefab,
        on_ready = on_ready,
    }
end

local function create_simple_triangles()
    -- local function add_v(vertices, p, n, t)
    --     local px, py, pz = math3d.index(p, 1, 2, 3)
    --     local q = mu.pack_tangent_frame(n, t)
    --     vertices[#vertices+1] = px
    --     vertices[#vertices+1] = py
    --     vertices[#vertices+1] = py

    --     local qx, qy, qz, qw = math3d.index(q, 1, 2, 3, 4)
    --     vertices[#vertices+1] = qx
    --     vertices[#vertices+1] = qy
    --     vertices[#vertices+1] = qz
    --     vertices[#vertices+1] = qw
    -- end
    -- local vertices = {}
    -- local n, t = math3d.normalize(math3d.vector(1, 10, 0)), math3d.normalize(math3d.vector(1.0, 0.0, 0.0))
    -- add_v(vertices, math3d.vector(0.0, 0.0, 0.0), n, t)
    -- add_v(vertices, math3d.vector(0.0, 0.0, 1.0), n, t)
    -- add_v(vertices, math3d.vector(1.0, 0.0, 0.0), n, t)
    local nx, ny, nz = math3d.index(math3d.normalize(math3d.vector(0, 1, 0.0)), 1, 2, 3, 4)
    local pp, np = 0.5, -0.5

    local py = 0

    world:create_entity{
        policy = {
            "ant.render|simplerender",
        },
        data = {
            simplemesh = {
                vb = {
                    start = 0,
                    num = 6,
                    handle = bgfx.create_vertex_buffer(("ffffffffffff"):rep(6):pack(
                        np, py, np, nx, ny, nz, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0,
                        np, py, pp, nx, ny, nz, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0,
                        pp, py, pp, nx, ny, nz, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0,
                        pp, py, pp, nx, ny, nz, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0,
                        pp, py, np, nx, ny, nz, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0,
                        np, py, np, nx, ny, nz, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0), layoutmgr.get "p3|n3|T4|t2".handle)
                },
            },
            material = "/pkg/ant.test.light/assets/materials/default.material",

            visible_state  = "main_view",
            render_layer = "opacity",
            scene = {
                --r = {0.0, 0.0, 0.8},
                s = 1000,
                --t = {0.0, 1.0, 0.0}
            },
        }
    }

    -- local p1 = math3d.vector(0.0, 0.0, 1.0)
    -- local p2 = math3d.vector(0.0, 1.0, 2.0)
    -- local p3 = math3d.vector(1.0, 0.0, 2.0)

    -- local n = math3d.normalize(math3d.cross(math3d.sub(p2, p1), math3d.sub(p3, p1)))
    -- print(math3d.tostring(n))
end


function S.init()
    create_instance( "/pkg/ant.test.light/assets/light.prefab", function (e)
        local leid = e.tag['*'][2]
        local le<close> = world:entity(leid, "directional_light scene:update")

        local r2l_mat<const> = mc.R2L_MAT
        local v = math3d.transform(r2l_mat, math3d.vector(0.424264073, -0.707106769, -0.565685451), 0)
        iom.set_direction(le, v)
    end)

end

local function test_lines()
    local pw, nw = 0.5, -0.5
    local ld = 100
    world:create_entity{
        policy = {
            "ant.render|simplerender",
        },
        data = {
            simplemesh = {
                vb = {
                    start = 0,
                    num = 4,
                    handle = bgfx.create_vertex_buffer(("fffff"):rep(4):pack(
                        nw, 0.0, 0.0, 0.0, 1.0,
                        nw, 0.0, ld,  0.0, 0.0,
                        pw, 0.0, 0.0, 1.0, 0.0,
                        pw, 0.0, ld,  1.0, 1.0), layoutmgr.get "p3|t2".handle)
                },
                ib = irender.quad_ibobj(6)
            },
            material = "/pkg/ant.test.light/assets/materials/line_test.material",
            visible_state  = "main_view",
            render_layer = "translucent",
            scene = {},
        }
    }
end


function S.init_world()
    local mq = w:first "main_queue camera_ref:in"
    local ce<close> = world:entity(mq.camera_ref, "camera:in")
    local eyepos = math3d.vector(0, 10, -10)
    iom.set_position(ce, eyepos)
    local dir = math3d.normalize(math3d.sub(math3d.vector(0.0, 0.0, 0.0, 1.0), eyepos))
    iom.set_direction(ce, dir)

    test_lines()
    -- create_simple_triangles()

    -- create_instance("/pkg/ant.test.light/assets/building_station.prefab", function (e)
    --     local leid = e.tag['*'][1]
    --     local le<close> = world:entity(leid, "scene:update")
    --     iom.set_scale(le, 0.1)
    -- end)

--[[     create_instance("/pkg/ant.resources.binary/meshes/base/cube.glb|mesh.prefab", function (e)
        -- local le<close> = world:entity(leid, "scene:update")
        -- iom.set_scale(le, 0.1)
    end) ]]

    -- create_instance("/pkg/ant.test.light/assets/world_simple.glb|mesh.prefab", function (e)
    --     peids = e.tag['*']
    --     local leid = e.tag['*'][1]
    --     local le<close> = world:entity(leid, "scene:update")
    --     iom.set_scale(le, 0.1)
    -- end)

    -- create_instance("/pkg/ant.test.light/assets/plane.glb|mesh.prefab", function (e)
    --     local normaltex = assetmgr.resource "/pkg/ant.test.light/assets/normal.texture"
    --     local leidobj = e.tag['*'][2]
    --     local obj<close> = world:entity(leidobj)

    --     imaterial.set_property(obj, "s_normal", normaltex.id)
    -- end)

    -- create_instance("/pkg/ant.test.light/assets/ground_01.glb|mesh.prefab", function (e)
    --     local leid = e.tag['*'][1]
    --     local le<close> = world:entity(leid, "scene:update")
    --     iom.set_scale(le, 0.1)
    --     iom.set_position(le, math3d.vector(5, 0, 0))
    -- end)

    -- world:create_entity{
    --     policy = {
    --         "ant.render|render",
    --     },
    --     data = {
    --         material = "/pkg/ant.test.light/assets/materials/default.material",
    --         mesh = "/pkg/ant.test.light/assets/ground_01.glb|meshes/Plane.007_P1.meshbin",
    --         scene = {
    --             s = 0.1
    --         },
    --         visible_state = "main_view",
    --     }
    -- }

    --create_simple_triangles()

    --create_simple_triangles()
    -- iom.set_position(camera_ref, math3d.vector(0, 2, -5))
    -- iom.set_direction(camera_ref, math3d.vector(0.0, 0.0, 1.0))
end
