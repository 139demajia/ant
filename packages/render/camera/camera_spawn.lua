local ecs = ...
local world = ecs.world
local mathpkg = import_package "ant.math"
local mc = mathpkg.constant
local defaultcomp = require "components.default"

local m = ecs.interface "camera"

function m.create(info)
    local frustum = info.frustum
    if not frustum then
        local mq = world:singleton_entity "main_queue"
        local vr = mq.render_target.viewport.rect
        frustum = defaultcomp.frustum(vr.w, vr.h)
        frustum.f = 300
    end

    local locktarget = info.locktarget

    local policy = {
        "ant.render|camera",
        "ant.general|name",
    }

    if locktarget then
        policy[#policy+1] = "ant.objcontroller|camera_lock"
    end

    local camera_data = {
        type    = info.type     or "",
        eyepos  = world.component:vector(info.eyepos   or mc.T_ZERO_PT),
        viewdir = world.component:vector(info.viewdir  or mc.T_ZAXIS),
        updir   = world.component:vector(info.updir    or mc.T_YAXIS),
        frustum = frustum,
    }
    return world:create_entity {
        policy = policy,
        data = {
            camera = camera_data,
            name = info.name or "DEFAULT_CAMERA",
            lock_target = locktarget,
        }
    }
end

function m.bind(id, which_queue)
    local q = world:singleton_entity(which_queue)
    if q == nil then
        error(string.format("not find queue:%s", which_queue))
    end
    q.camera_eid = id
end

function m.get(id)
    return world[id].camera
end
