local gui_main = import_package "ant.imgui".gui_main
local GuiLogView = import_package "ant.imgui".editor.gui_logview
local GuiSysInfo = import_package "ant.imgui".editor.gui_sysinfo
local GuiSceneHierarchyView = import_package "ant.imgui".editor.gui_scene_hierarchy_view
local GuiPropertyView = import_package "ant.imgui".editor.gui_property_view
local GuiComponentStyle = import_package "ant.imgui".editor.gui_component_style
local GuiScriptRunner = import_package "ant.imgui".editor.gui_script_runner
local GuiShaderWatch = import_package "ant.imgui".editor.gui_shader_watch
local GuiSystemProfiler = import_package "ant.imgui".editor.gui_system_profiler
local GuiProjectView = import_package "ant.imgui".editor.gui_project_view
local GuiInspectorView = import_package "ant.imgui".editor.gui_inspector_view
local GuiProjectList = import_package "ant.imgui".editor.gui_project_list
local GuiWindowController = import_package "ant.imgui".editor.gui_window_controller
local GuiPolicyComponentPair = import_package "ant.imgui".editor.gui_policy_component_pair
local GuiAddPolicyView = import_package "ant.imgui".editor.gui_add_policy_view
local GuiMsgWatchView = import_package "ant.imgui".editor.gui_msg_watch_view
local EntityMgr = import_package "ant.imgui".editor.entity_mgr
local gui_mgr = import_package "ant.imgui".gui_mgr
local args = {
    screen_width = 1680,
    screen_height = 960,
}
local main = {}
function main.init()
    local EditorInfo = import_package "ant.imgui".editor_info
    EditorInfo.init({
        Package = "ant.imgui_editor",
        PackageFSPath = "/pkg/ant.imgui_editor",
    })

    local TestGuiBase = require "test_gui_base"
    local GuiEditorMenu = require "gui_editor_menu"
    local GuiScene = require "gui_scene"

    gui_mgr.register(EntityMgr.MgrName,EntityMgr.new())
   
    gui_mgr.register(GuiEditorMenu.GuiName,GuiEditorMenu.new())

    gui_mgr.register(GuiScene.GuiName,GuiScene.new())
    gui_mgr.register(GuiSysInfo.GuiName,GuiSysInfo.new())
    gui_mgr.register(GuiSceneHierarchyView.GuiName,GuiSceneHierarchyView.new())
    gui_mgr.register(GuiPropertyView.GuiName,GuiPropertyView.new())
    gui_mgr.register(GuiComponentStyle.GuiName,GuiComponentStyle.new())
    local log_view = GuiLogView.new()

    gui_mgr.register(GuiLogView.GuiName,log_view)

    local testgui = TestGuiBase.new(true)
    gui_mgr.register(TestGuiBase.GuiName,testgui)

    gui_mgr.register(GuiScriptRunner.GuiName,GuiScriptRunner.new())
    gui_mgr.register(GuiShaderWatch.GuiName,GuiShaderWatch.new())
    gui_mgr.register(GuiSystemProfiler.GuiName,GuiSystemProfiler.new())
    gui_mgr.register(GuiProjectView.GuiName,GuiProjectView.new())
    gui_mgr.register(GuiInspectorView.GuiName,GuiInspectorView.new())
    gui_mgr.register(GuiProjectList.GuiName,GuiProjectList.new())
    gui_mgr.register(GuiWindowController.GuiName,GuiWindowController.new())
    gui_mgr.register(GuiPolicyComponentPair.GuiName,GuiPolicyComponentPair.new())
    local default_value_cfg = require "engine_data.default_value_override"
    gui_mgr.register(GuiAddPolicyView.GuiName,GuiAddPolicyView.new(default_value_cfg))
    gui_mgr.register(GuiMsgWatchView.GuiName,GuiMsgWatchView.new())
end


gui_main.run(main,args)