local ecs = ...
local world = ecs.world
local w = world.w

local gizmo     = ecs.require "gizmo.gizmo"
local imgui     = require "imgui"
local uiconfig  = require "widget.config"

local base_panel        = ecs.require "widget.base_view"()
local light_panel       = ecs.require "widget.light_view"()
local material_panel    = ecs.require "widget.material_view"()
local slot_panel        = ecs.require "widget.slot_view"()
local collider_panel    = ecs.require "widget.collider_view"()
local effect_panel      = ecs.require "widget.effect_view"()
local skybox_panel      = ecs.require "widget.skybox_view"()
local camera_panel      = ecs.require "widget.camera_view"()

local m = {}
local current_panel
local current_eid

local function update_ui_data(eid)
    if not current_panel or not eid then return end
    -- update transform
    -- if current_panel.super then
    --     -- BaseView
    --     current_panel.super.update(current_panel)
    -- else
        current_panel:update()
    --end
end

function m.update_ui(ut)
    if not gizmo.target_eid then return end
    update_ui_data(gizmo.target_eid)
end

local function update_eid()
    if current_eid == gizmo.target_eid then
        return
    end
    current_eid = gizmo.target_eid
    --
    base_panel:reset_disable()
    camera_panel:set_eid(current_eid, base_panel)
    light_panel:set_eid(current_eid, base_panel)
    slot_panel:set_eid(current_eid)
    collider_panel:set_eid(current_eid)
    effect_panel:set_eid(current_eid)
    skybox_panel:set_eid(current_eid)
    material_panel:set_eid(current_eid)
    base_panel:set_eid(current_eid)
end

function m.show()
    update_eid()
    local viewport = imgui.GetMainViewport()
    imgui.windows.SetNextWindowPos(viewport.WorkPos[1] + viewport.WorkSize[1] - uiconfig.PropertyWidgetWidth, viewport.WorkPos[2] + uiconfig.ToolBarHeight, 'F')
    imgui.windows.SetNextWindowSize(uiconfig.PropertyWidgetWidth, viewport.WorkSize[2] - uiconfig.BottomWidgetHeight - uiconfig.ToolBarHeight, 'F')
    if imgui.windows.Begin("Inspector", imgui.flags.Window { "NoCollapse", "NoClosed" }) then
        base_panel:show()
        camera_panel:show()
        light_panel:show()
        slot_panel:show()
        collider_panel:show()
        effect_panel:show()
        skybox_panel:show()
        material_panel:show()
    end
    imgui.windows.End()
end

return m