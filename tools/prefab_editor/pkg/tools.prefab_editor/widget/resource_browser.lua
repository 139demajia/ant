local ecs = ...
local world = ecs.world
local w = world.w
local assetmgr  = import_package "ant.asset"

local imgui     = require "imgui"
local fw        = require "bee.filewatch"
local lfs       = require "filesystem.local"
local fs        = require "filesystem"
local uiconfig  = require "widget.config"
local uiutils   = require "widget.utils"
local utils     = require "common.utils"
local gd        = require "common.global_data"
local icons     = require "common.icons"(assetmgr)
local faicons   = require "common.fa_icons"
local editor_setting=require "editor_setting"

local m = {
    dirty = true
}

local resource_tree = nil
local selected_folder = {files = {}}
local selected_file = nil

local preview_images = {}
local texture_detail = {}

local function on_drop_files(files)
    local current_path = lfs.path(tostring(selected_folder[1]))
    for k, v in pairs(files) do
        local path = lfs.path(v)
        local dst_path = current_path / tostring(path:filename())
        if lfs.is_directory(path) then
            lfs.create_directories(dst_path)
            lfs.copy(path, dst_path, true)
        else
            lfs.copy_file(path, dst_path, fs.copy_options.overwrite_existing)
        end
    end
end

local function path_split(fullname)
    local root = (fullname:sub(1, 1) == "/") and "/" or ""
    local stack = {}
	for elem in fullname:gmatch("([^/\\]+)[/\\]?") do
        if #elem == 0 and #stack ~= 0 then
        elseif elem == '..' and #stack ~= 0 and stack[#stack] ~= '..' then
            stack[#stack] = nil
        elseif elem ~= '.' then
            stack[#stack + 1] = elem
        end
    end
    return root, stack
end

local function construct_resource_tree(fspath)
    local tree = {files = {}, dirs = {}}
    if fspath then
        local sorted_path = {}
        for item in fs.pairs(fspath) do
            sorted_path[#sorted_path+1] = item
        end
        table.sort(sorted_path, function(a, b) return string.lower(tostring(a)) < string.lower(tostring(b)) end)
        for _, item in ipairs(sorted_path) do
            local ext = item:extension():string()
            if fs.is_directory(item) and ext ~= ".glb" and ext ~= ".png" and ext ~= ".material" and ext ~= ".texture" then
                table.insert(tree.dirs, {item, construct_resource_tree(item), parent = {tree}})
                if selected_folder[1] == item then
                    selected_folder = tree.dirs[#tree.dirs]
                end
            else
                table.insert(tree.files, item)
            end
        end
    end
    return tree
end

local engine_package_resources = {
    "ant.resources",
    "ant.resources.binary",
}

function m.update_resource_tree(hiden_engine_res)
    if not m.dirty or not gd.project_root then return end
    resource_tree = {files = {}, dirs = {}}
    local packages
    if hiden_engine_res then
        packages = {}
        for _, p in ipairs(gd.packages) do
            local isengine
            for _, ep in ipairs(engine_package_resources) do
                if p.name == ep then
                    isengine = true
                    break
                end
            end

            if not isengine then
                packages[#packages+1] = p
            end
        end
    else
        packages = gd.packages
    end
    for _, item in ipairs(packages) do
        local path = fs.path("/pkg") / fs.path(item.name)
        resource_tree.dirs[#resource_tree.dirs + 1] = {path, construct_resource_tree(path)}
    end

    local function set_parent(tree)
        for _, v in pairs(tree[2].dirs) do
            v.parent = tree
            set_parent(v)
        end
    end

    for _, tree in ipairs(resource_tree.dirs) do
        set_parent(tree)
    end
    if not selected_folder[1] then
        selected_folder = resource_tree.dirs[1]
    end
    m.dirty = false
end

local renaming = false
local new_filename = {text = "noname"}
local function rename_file(file)
    if not renaming then return end

    if not imgui.windows.IsPopupOpen("Rename file") then
        imgui.windows.OpenPopup("Rename file")
    end

    local change, opened = imgui.windows.BeginPopupModal("Rename file", imgui.flags.Window{"AlwaysAutoResize"})
    if change then
        imgui.widget.Text("new name :")
        imgui.cursor.SameLine()
        if imgui.widget.InputText("##NewName", new_filename) then
        end
        imgui.cursor.SameLine()
        if imgui.widget.Button(faicons.ICON_FA_SQUARE_CHECK.." OK") then
            lfs.rename(file:localpath(), file:parent_path():localpath() / tostring(new_filename.text))
            renaming = false
        end
        imgui.cursor.SameLine()
        if imgui.widget.Button(faicons.ICON_FA_SQUARE_XMARK.." Cancel") then
            renaming = false
        end
        imgui.windows.EndPopup()
    end
end

local function ShowContextMenu()
    if imgui.windows.BeginPopupContextItem(tostring(selected_file:filename())) then
        if imgui.widget.MenuItem(faicons.ICON_FA_UP_RIGHT_FROM_SQUARE.." Reveal in Explorer", "Alt+Shift+R") then
            os.execute("c:\\windows\\explorer.exe /select,"..selected_file:localpath():string():gsub("/","\\"))
        end
        if imgui.widget.MenuItem(faicons.ICON_FA_PEN.." Rename", "F2") then
            renaming = true
            new_filename.text = tostring(selected_file:filename())
        end
        imgui.cursor.Separator()
        if imgui.widget.MenuItem(faicons.ICON_FA_TRASH.." Delete", "Delete") then
            lfs.remove(selected_file:localpath())
            selected_file = nil
        end
        imgui.windows.EndPopup()
    end
end

function m.show()
    if not gd.project_root then
        return
    end
    local type, path = fw.select()
    while type do
        if (not string.find(path, "\\.build\\"))
            and (not string.find(path, "\\.log\\"))
            and (not string.find(path, "\\.repo\\")) then
            m.dirty = true
        end
        type, path = fw.select()
    end

    local viewport = imgui.GetMainViewport()
    imgui.windows.SetNextWindowPos(viewport.WorkPos[1], viewport.WorkPos[2] + viewport.WorkSize[2] - uiconfig.BottomWidgetHeight, 'F')
    imgui.windows.SetNextWindowSize(viewport.WorkSize[1], uiconfig.BottomWidgetHeight, 'F')
    m.update_resource_tree(editor_setting.setting.hide_engine_resource)

    local function do_show_browser(folder)
        for k, v in pairs(folder.dirs) do
            local dir_name = tostring(v[1]:filename())
            local base_flags = imgui.flags.TreeNode { "OpenOnArrow", "SpanFullWidth" } | ((selected_folder == v) and imgui.flags.TreeNode{"Selected"} or 0)
            local skip = false
            if not v.parent then
                imgui.widget.Image(assetmgr.textures[icons.ICON_ROOM_INSTANCE.id], icons.ICON_ROOM_INSTANCE.texinfo.width, icons.ICON_ROOM_INSTANCE.texinfo.height)
                imgui.cursor.SameLine()
            end
            if (#v[2].dirs == 0) then
                imgui.widget.TreeNode(dir_name, base_flags | imgui.flags.TreeNode { "Leaf", "NoTreePushOnOpen" })
            else
                local adjust_flags = base_flags | (string.find(selected_folder[1]._value, "/" .. dir_name) and imgui.flags.TreeNode {"DefaultOpen"} or 0)
                if imgui.widget.TreeNode(dir_name, adjust_flags) then
                    if imgui.util.IsItemClicked() then
                        selected_folder = v
                    end
                    skip = true
                    do_show_browser(v[2])
                    imgui.widget.TreePop()
                end
            end
            if not skip and imgui.util.IsItemClicked() then
                selected_folder = v
            end
        end 
    end
    if imgui.windows.Begin("ResourceBrowser", imgui.flags.Window { "NoCollapse", "NoScrollbar", "NoClosed" }) then
        imgui.windows.PushStyleVar(imgui.enum.StyleVar.ItemSpacing, 0, 6)
        local _, split_dirs = path_split(selected_folder[1]:string())
        for i = 1, #split_dirs do
            if imgui.widget.Button("/" .. split_dirs[i]) then
                if tostring(selected_folder[1]:filename()) ~= split_dirs[i] then
                    local lookup_dir = selected_folder.parent
                    while lookup_dir do
                        if tostring(lookup_dir[1]:filename()) == split_dirs[i] then
                            selected_folder = lookup_dir
                            lookup_dir = nil
                        else
                            lookup_dir = lookup_dir.parent
                        end
                    end
                end
            end
            imgui.cursor.SameLine() --last SameLine for 'HideEngineResource' button
        end
        local cb = {editor_setting.setting.hide_engine_resource}
        if imgui.widget.Checkbox("HideEngineResource", cb) then
            editor_setting.setting.hide_engine_resource = cb[1]
            editor_setting.save()
            m.dirty = true
            m.update_resource_tree(editor_setting.setting.hide_engine_resource)
        end
        imgui.windows.PopStyleVar(1)
        imgui.cursor.Separator()

        --imgui.deprecated.Columns(3)
        if imgui.table.Begin("InspectorTable", 3, imgui.flags.Table {'Resizable', 'ScrollY'}) then
            imgui.table.NextColumn()
            local child_width, child_height = imgui.windows.GetContentRegionAvail()
            imgui.windows.BeginChild("##ResourceBrowserDir", child_width, child_height, false)
            do_show_browser(resource_tree)
            imgui.windows.EndChild()

            imgui.cursor.SameLine()
            imgui.table.NextColumn()
            child_width, child_height = imgui.windows.GetContentRegionAvail()
            imgui.windows.BeginChild("##ResourceBrowserContent", child_width, child_height, false);
            local folder = selected_folder[2]
            if folder then
                rename_file(selected_file)
                for _, path in pairs(folder.dirs) do
                    imgui.widget.Image(assetmgr.textures[icons.ICON_FOLD.id], icons.ICON_FOLD.texinfo.width, icons.ICON_FOLD.texinfo.height)
                    imgui.cursor.SameLine()
                    if imgui.widget.Selectable(tostring(path[1]:filename()), selected_file == path[1], 0, 0, imgui.flags.Selectable {"AllowDoubleClick"}) then
                        selected_file = path[1]
                        if imgui.util.IsMouseDoubleClicked(0) then
                            selected_folder = path
                        end
                    end
                    if selected_file == path[1] then
                        ShowContextMenu()
                    end
                end
                for _, path in pairs(folder.files) do
                    local icon = icons.get_file_icon(path)
                    imgui.widget.Image(assetmgr.textures[icon.id], icon.texinfo.width, icon.texinfo.height)
                    imgui.cursor.SameLine()
                    if imgui.widget.Selectable(tostring(path:filename()), selected_file == path, 0, 0, imgui.flags.Selectable {"AllowDoubleClick"}) then
                        selected_file = path
                        if imgui.util.IsMouseDoubleClicked(0) then
                            local prefab_file
                            if path:equal_extension(".prefab") then
                                prefab_file = tostring(path)
                            elseif path:equal_extension(".glb") then
                                prefab_file = tostring(path) .. "|mesh.prefab"
                            elseif path:equal_extension(".fbx") then
                                world:pub {"OpenFile", "FBX", tostring(path)}
                            elseif path:equal_extension ".material" then
                                local me = ecs.require "widget.material_editor"
                                me.open(path)
                            end
                            if prefab_file then
                                world:pub {"OpenFile", "Prefab", prefab_file}
                            end
                        end
                        if path:equal_extension(".png") then
                            if not preview_images[selected_file] then
                                local pkg_path = path:string()
                                preview_images[selected_file] = assetmgr.resource(pkg_path, { compile = true })
                            end
                        end

                        if path:equal_extension(".texture") then
                            if not texture_detail[selected_file] then
                                local pkg_path = path:string()
                                texture_detail[selected_file] = utils.readtable(pkg_path)
                                local t = assetmgr.resource(pkg_path)
                                local s = t.sampler
                                preview_images[selected_file] = t._data
                            end
                        end
                    end
                    if selected_file == path then
                        ShowContextMenu()
                    end
                    if path:equal_extension(".material")
                        or path:equal_extension(".texture")
                        or path:equal_extension(".png")
                        or path:equal_extension(".dds")
                        or path:equal_extension(".prefab")
                        or path:equal_extension(".glb")
                        or path:equal_extension(".efk")
                        or path:equal_extension(".lua") then
                        if imgui.widget.BeginDragDropSource() then
                            imgui.widget.SetDragDropPayload("DragFile", tostring(path))
                            imgui.widget.EndDragDropSource()
                        end
                    end
                end
            end
            imgui.windows.EndChild()

            imgui.cursor.SameLine()
            imgui.table.NextColumn()
            child_width, child_height = imgui.windows.GetContentRegionAvail()
            imgui.windows.BeginChild("##ResourceBrowserPreview", child_width, child_height, false);
            if fs.path(selected_file):equal_extension(".png") or fs.path(selected_file):equal_extension(".texture") then
                local preview = preview_images[selected_file]
                if preview then
                    if texture_detail[selected_file] then
                        imgui.widget.Text("image:" .. tostring(texture_detail[selected_file].path))
                    end
                    -- imgui.deprecated.Columns(2, "PreviewColumns", true)
                    imgui.widget.Text(preview.texinfo.width .. "x" .. preview.texinfo.height .. " ".. preview.texinfo.bitsPerPixel)
                    local width, height = preview.texinfo.width, preview.texinfo.height
                    if width > 180 then
                        width = 180
                    end
                    if height > 180 then
                        height = 180
                    end
                    imgui.widget.Image(assetmgr.textures[preview.id], width, height)
                    imgui.cursor.SameLine()
                    local texture_info = texture_detail[selected_file] 
                    if texture_info then
                        imgui.widget.Text(("Compress:\n  android: %s\n  ios: %s\n  windows: %s \nSampler:\n  MAG: %s\n  MIN: %s\n  MIP: %s\n  U: %s\n  V: %s"):format( 
                            texture_info.compress and texture_info.compress.android or "raw",
                            texture_info.compress and texture_info.compress.ios or "raw",
                            texture_info.compress and texture_info.compress.windows or "raw",
                            texture_info.sampler.MAG,
                            texture_info.sampler.MIN,
                            texture_info.sampler.MIP,
                            texture_info.sampler.U,
                            texture_info.sampler.V
                            ))
                    end
                end
            end
            imgui.windows.EndChild()
        imgui.table.End()
        end
    end
    imgui.windows.End()
end

function m.selected_file()
    return selected_file
end

function m.selected_folder()
    return selected_folder
end

return m