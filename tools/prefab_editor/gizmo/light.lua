local ecs = ...
local world = ecs.world
local w = world.w

local imaterial = ecs.import.interface "ant.asset|imaterial"
local computil  = ecs.import.interface "ant.render|ientity"
local ilight    = ecs.import.interface "ant.render|ilight"
local iom       = ecs.import.interface "ant.objcontroller|iobj_motion"
local ivs       = ecs.import.interface "ant.scene|ivisible_state"
local geo_utils = ecs.require "editor.geometry_utils"

local math3d = require "math3d"
local gizmo_const = require "gizmo.const"
local bgfx = require "bgfx"

local m = {
    directional = {
        eid = {}
    },
    point = {
        eid = {}
    },
    spot = {
        eid = {}
    },
    billboard = {}
}
local NORMAL_COLOR = {1, 1, 1, 1}
local HIGHLIGHT_COLOR = {0.5, 0.5, 0, 1}
local RADIUS = 0.25
local SLICES = 10
local LENGTH = 1
local DEFAULT_POSITION = {0, 0, 0}
local DEFAULT_ROTATE = {2.4, 0, 0}

function m.bind(eid)
    m.show(false)
    m.current_light = eid
    m.current_gizmo = nil
    if not eid then return end 
    local ec = world:entity(eid)
    local lt = ec.light.type
    m.current_gizmo = m[lt]
    if m.current_gizmo then
        m.update_gizmo()
        local er = world:entity(m.current_gizmo.root)
        iom.set_position(er, iom.get_position(ec))
        iom.set_rotation(er, iom.get_rotation(ec))
        er.name = ec.name
        m.show(true)
    end
end

function m.update()
    local er = world:entity(m.current_gizmo.root)
    local ec = world:entity(m.current_light)
    iom.set_position(er, iom.get_position(ec))
    iom.set_rotation(er, iom.get_rotation(ec))
    world:pub{"component_changed", "light", m.current_light, "transform"}
end

function m.show(b)
    if m.current_gizmo then
        for i, eid in ipairs(m.current_gizmo.eid) do
            ivs.set_state(world:entity(eid), "main_view", b)
        end
    end
end

function m.highlight(b)
    if not m.current_gizmo then return end

    if b then
        for _, eid in ipairs(m.current_gizmo.eid) do
            imaterial.set_property(world:entity(eid), "u_color", gizmo_const.COLOR.HIGHLIGHT)
        end
    else
        for _, eid in ipairs(m.current_gizmo.eid) do
            imaterial.set_property(world:entity(eid), "u_color", math3d.vector(gizmo_const.COLOR.GRAY))
        end
    end
end

local function create_gizmo_root(initpos, introt)
    return ecs.create_entity{
		policy = {
			"ant.general|name",
            "ant.scene|scene_object",
		},
		data = {
			name = "gizmo root",
            scene = {t = initpos or {0,0,0}, r = introt or {0,0,0,1}},
            -- on_ready = function (e)
            --     ivs.set_state(e, "visible", false)  
            -- end
		},
    }
end

local function create_directional_gizmo(initpos, introt)
    local root = create_gizmo_root(initpos, introt)
    local circle_eid = computil.create_circle_entity("directional gizmo circle", RADIUS, SLICES, {parent = root}, gizmo_const.COLOR.GRAY, true)
    local alleid = {}
    alleid[#alleid + 1] = circle_eid
    local radian_step = 2 * math.pi / SLICES
    for s=0, SLICES-1 do
        local radian = radian_step * s
        local x, y = math.cos(radian) * RADIUS, math.sin(radian) * RADIUS
        local line_eid = computil.create_line_entity("", {x, y, 0}, {x, y, LENGTH}, {parent = root}, gizmo_const.COLOR.GRAY, true)
        alleid[#alleid + 1] = line_eid
    end
    m.directional.root = root
    m.directional.eid = alleid
end

local function update_circle_vb(eid, radian)
    local rc = world:entity(eid).render_object
    local vbdesc, ibdesc = rc.vb, rc.ib
    local vb, _ = geo_utils.get_circle_vb_ib(radian, gizmo_const.ROTATE_SLICES)
    bgfx.update(vbdesc.handles[1], 0, bgfx.memory_buffer("fffd", vb));
end

local function update_point_gizmo()
    local root = m.point.root
    local radius = m.current_light and ilight.range(world:entity(m.current_light)) or 1.0
    
    if #m.point.eid == 0 then
        local c0 = geo_utils.create_dynamic_circle("light gizmo circle", radius, gizmo_const.ROTATE_SLICES, {parent = root}, gizmo_const.COLOR.GRAY, true)
        local c1 = geo_utils.create_dynamic_circle("light gizmo circle", radius, gizmo_const.ROTATE_SLICES, {parent = root, r = math3d.tovalue(math3d.quaternion{0, math.rad(90), 0})}, gizmo_const.COLOR.GRAY, true)
        local c2 = geo_utils.create_dynamic_circle("light gizmo circle", radius, gizmo_const.ROTATE_SLICES, {parent = root, r = math3d.tovalue(math3d.quaternion{math.rad(90), 0, 0})}, gizmo_const.COLOR.GRAY, true)
        m.point.eid = {c0, c1, c2}
    else
        update_circle_vb(m.point.eid[1], radius)
        update_circle_vb(m.point.eid[2], radius)
        update_circle_vb(m.point.eid[3], radius)
    end
end

local function update_spot_gizmo()
    local range = 1.0
    local radian = 10
    if m.current_light then
        range = ilight.range(world:entity(m.current_light))
        radian = ilight.outter_radian(world:entity(m.current_light)) or 10
    end
    local radius = range * math.tan(radian * 0.5)
    if #m.spot.eid == 0 then
        local root = m.spot.root
        local c0 = geo_utils.create_dynamic_circle("light gizmo circle", radius, gizmo_const.ROTATE_SLICES, {parent = root, t = {0, 0, range}}, gizmo_const.COLOR.GRAY, true)
        local line0 = geo_utils.create_dynamic_line("line", {0, 0, 0}, {0, radius, range}, {parent = root}, gizmo_const.COLOR.GRAY, true)
        local line1 = geo_utils.create_dynamic_line("line", {0, 0, 0}, {radius, 0, range}, {parent = root}, gizmo_const.COLOR.GRAY, true)
        local line2 = geo_utils.create_dynamic_line("line", {0, 0, 0}, {0, -radius, range}, {parent = root}, gizmo_const.COLOR.GRAY, true)
        local line3 = geo_utils.create_dynamic_line("line", {0, 0, 0}, {-radius, 0, range}, {parent = root}, gizmo_const.COLOR.GRAY, true)
        local line4 = geo_utils.create_dynamic_line("line", {0, 0, 0}, {0, 0, range}, {parent = root}, gizmo_const.COLOR.GRAY, true)
        m.spot.eid = {line0, line1, line2, line3, line4, c0}
    else
        update_circle_vb(m.spot.eid[6], radius)
        iom.set_position(world:entity(m.spot.eid[6]), {0, 0, range})

        local function update_vb(eid, tp2)
            local vbdesc = world:entity(eid).render_object.vb
            bgfx.update(vbdesc.handles[1], 0, bgfx.memory_buffer("fffd", {0, 0, 0, 0xffffffff, tp2[1], tp2[2], tp2[3], 0xffffffff}));
        end
        update_vb(m.spot.eid[1], {0, radius, range})
        update_vb(m.spot.eid[2], {radius, 0, range})
        update_vb(m.spot.eid[3], {0, -radius, range})
        update_vb(m.spot.eid[4], {-radius, 0, range})
        update_vb(m.spot.eid[5], {0, 0, range})
    end
end

function m.update_gizmo()
    if m.current_gizmo == m.spot then
        update_spot_gizmo()
    elseif m.current_gizmo == m.point then
        update_point_gizmo()
    end
end

function m.clear()
    for _,v in pairs(m.billboard) do
        world:remove_entity(v)
    end
    m.billboard = {}
    m.current_light = nil
    m.show(false)
end

function m.on_remove_light(eid)
    --if not m.billboard[eid] then return end
    --world:remove_entity(m.billboard[eid])
    m.billboard[eid] = nil
    -- m.current_light = nil
    -- m.show(false)
    m.bind(nil)
end

local inited = false
function m.init()
    if inited then return end
    create_directional_gizmo(m.current_light and iom.get_position(world:entity(m.current_light)) or nil, m.current_light and iom.get_rotation(world:entity(m.current_light)) or nil)
    m.point.root = create_gizmo_root()
    update_point_gizmo()
    m.spot.root = create_gizmo_root()
    update_spot_gizmo()
    inited = true
end

return m