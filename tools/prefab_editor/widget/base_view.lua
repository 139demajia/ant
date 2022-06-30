local ecs = ...
local world = ecs.world
local w = world.w

local prefab_mgr    = ecs.require "prefab_manager"
local iom           = ecs.import.interface "ant.objcontroller|iobj_motion"
local gizmo         = ecs.require "gizmo.gizmo"

local utils         = require "common.utils"
local math3d        = require "math3d"
local uiproperty    = require "widget.uiproperty"
local hierarchy     = require "hierarchy_edit"
local BaseView      = require "widget.view_class".BaseView

function BaseView:_init()
    local base = {}
    base["script"]   = uiproperty.ResourcePath({label = "Script", extension = ".lua"})
    base["prefab"]   = uiproperty.EditText({label = "Prefabe", readonly = true})
    base["preview"]  = uiproperty.Bool({label = "OnlyPreview"})
    base["name"]     = uiproperty.EditText({label = "Name"})
    base["tag"]      = uiproperty.EditText({label = "Tag"})
    base["position"] = uiproperty.Float({label = "Position", dim = 3, speed = 0.1})
    base["rotate"]   = uiproperty.Float({label = "Rotate", dim = 3})
    base["scale"]    = uiproperty.Float({label = "Scale", dim = 3, speed = 0.05})
    
    self.base        = base
    self.general_property = uiproperty.Group({label = "General"}, base)
    --
    self.base.prefab:set_getter(function() return self:on_get_prefab() end)
    self.base.preview:set_setter(function(value) self:on_set_preview(value) end)      
    self.base.preview:set_getter(function() return self:on_get_preview() end)
    self.base.name:set_setter(function(value) self:on_set_name(value) end)      
    self.base.name:set_getter(function() return self:on_get_name() end)
    self.base.tag:set_setter(function(value) self:on_set_tag(value) end)      
    self.base.tag:set_getter(function() return self:on_get_tag() end)
    self.base.position:set_setter(function(value) self:on_set_position(value) end)
    self.base.position:set_getter(function() return self:on_get_position() end)
    self.base.rotate:set_setter(function(value) self:on_set_rotate(value) end)
    self.base.rotate:set_getter(function() return self:on_get_rotate() end)
    self.base.scale:set_setter(function(value) self:on_set_scale(value) end)
    self.base.scale:set_getter(function() return self:on_get_scale() end)
end

function BaseView:set_model(eid)
    if self.eid == eid then return false end
    --TODO: need remove 'eid', there is no more eid
    self.eid = eid
    if not self.eid then return false end

    local template = hierarchy:get_template(eid)
    self.is_prefab = template and template.filename
    local property = {}
    property[#property + 1] = self.base.name
    property[#property + 1] = self.base.tag
    property[#property + 1] = self.base.position
    if self:has_rotate() then
        property[#property + 1] = self.base.rotate
    end
    if self:has_scale() then
        property[#property + 1] = self.base.scale
    end
    self.general_property:set_subproperty(property)
    BaseView.update(self)
    return true
end

function BaseView:on_get_prefab()
    local template = hierarchy:get_template(self.eid)
    if template and template.filename then
        return template.filename
    end
end

function BaseView:on_set_preview(value)
    local template = hierarchy:get_template(self.eid)
    template.editor = value
end

function BaseView:on_get_preview()
    local template = hierarchy:get_template(self.eid)
    return template.editor
end

function BaseView:on_set_name(value)
    local template = hierarchy:get_template(self.eid)
    template.template.data.name = value
    local e = world:entity(self.eid)
    e.name = value
    world:pub {"EntityEvent", "name", self.eid, value}
end

function BaseView:on_get_name()
    local e = world:entity(self.eid)
    if type(e.name) == "number" then
        return tostring(e.name)
    end
    return e.name or ""
end

function BaseView:on_set_tag(value)
    local template = hierarchy:get_template(self.eid)
    local tags = {}
    value:gsub('[^|]*', function (w) tags[#tags+1] = w end)
    template.template.data.tag = tags
    world:pub {"EntityEvent", "tag", self.eid, tags}
end

function BaseView:on_get_tag()
    local template = hierarchy:get_template(self.eid)
    if not template or not template.template then return "" end
    local tags = template.template.data.tag
    if type(tags) == "table" then
        return table.concat(tags, "|")
    end
    return tags
end

function BaseView:on_set_position(value)
    local template = hierarchy:get_template(self.eid)
    if template.template then
        world:pub {"EntityEvent", "move", self.eid, template.template.data.scene.t or {0,0,0}, value}
        template.template.data.scene.t = value
    else
        world:pub {"EntityEvent", "move", self.eid, math3d.tovalue(iom.get_position(world:entity(self.eid))), value}
    end
end

function BaseView:on_get_position()
    local template = hierarchy:get_template(self.eid)
    if template.template then
        return template.template.data.scene.t or {0,0,0}
    else
        return math3d.totable(iom.get_position(world:entity(self.eid)))
    end
end

function BaseView:on_set_rotate(value)
    local template = hierarchy:get_template(self.eid)
    --local euler = world:entity(self.eid).oldeuler
    world:pub {"EntityEvent", "rotate", self.eid, { math.rad(value[1]), math.rad(value[2]), math.rad(value[3]) }, value}
    if template.template then
        template.template.data.scene.r = math3d.tovalue(math3d.quaternion{math.rad(value[1]), math.rad(value[2]), math.rad(value[3])})
    end
end

function BaseView:on_get_rotate()
    local template = hierarchy:get_template(self.eid)
    local r
    if template.template then
        r = template.template.data.scene.r or {0,0,0,1}
    else
        r = iom.get_rotation(world:entity(self.eid))
    end
    local rad = math3d.tovalue(math3d.quat2euler(r))
    local raweuler = { math.deg(rad[1]), math.deg(rad[2]), math.deg(rad[3]) }
    -- local e = world:entity(self.eid)
    -- e.oldeuler = raweuler
    return raweuler--e.oldeuler
end

function BaseView:on_set_scale(value)
    local template = hierarchy:get_template(self.eid)
    if template.template then
        world:pub {"EntityEvent", "scale", self.eid, template.template.data.scene.s or {1,1,1}, value}
        template.template.data.scene.s = value
    else
        world:pub {"EntityEvent", "scale", self.eid, math3d.tovalue(iom.get_scale(world:entity(self.eid))), value}
    end
end

function BaseView:on_get_scale()
    local template = hierarchy:get_template(self.eid)
    if template.template then
        local s = template.template.data.scene.s
        if s then
            return type(s) == "table" and s or {s, s, s}
        else
            return {1,1,1}
        end
    else
        return math3d.tovalue(iom.get_scale(world:entity(self.eid)))
    end
end

function BaseView:has_rotate()
    return true
end

function BaseView:has_scale()
    return true
end

function BaseView:update()
    if not self.eid then return end
    --self.base.script:update()
    if self.is_prefab then
        self.base.prefab:update()
        self.base.preview:update()
    end
    self.general_property:update()
end

function BaseView:show()
    if not self.eid then return end
    --self.base.script:show()
    if self.is_prefab then
        self.base.prefab:show()
        self.base.preview:show()
    end
    self.general_property:show()
end

return BaseView