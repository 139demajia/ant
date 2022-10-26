local serialize = import_package "ant.serialize"

local fs        = require "filesystem"
local lfs       = require "filesystem.local"
local datalist  = require "datalist"

local settingpath<const> = fs.path "/pkg/tools.prefab_editor/editor.settings"
local function read()
    local f<close> = fs.open(settingpath)
    if f then
        return datalist.parse(f:read "a")
    end
    return {}
end

local editor_setting = read()

local function save()
    local lpath
    if not fs.exists(settingpath) then
        local p = settingpath:parent_path()
        lpath = p:localpath() / settingpath:filename():string()
    else
        lpath = settingpath:localpath()
    end
    local f<close> = lfs.open(lpath, "w")
    local c = serialize.stringify(editor_setting)
    f:write(c)
end

local function update_lastproj(name, projpath, auto_import)
    local l = editor_setting.lastproj
    if l == nil then
        l = {}
        editor_setting.lastproj = l
    end

    l.name = name
    l.proj_path = projpath:gsub("\\", "/")
    l.auto_import = auto_import
end

local function add_recent_file(f)
    local function find_recent_file(f, rf)
        for idx, ff in ipairs(rf) do
            if ff == f then
                return idx
            end
        end
    end

    local rf = editor_setting.recent_files
    if rf == nil then
        rf = {}
        editor_setting.recent_files = rf
    end

    local idx = find_recent_file(f, rf)

    if idx == nil and #rf == 10 then
        idx = 10
    end

    if idx then
        table.remove(rf, idx)
    end
    table.insert(rf, 1, f)
    assert(#rf <= 10)
end

local function update_camera_setting(speed)
    local cs = editor_setting.camera
    if cs == nil then
        cs = {}
        editor_setting.camera = cs
    end
    cs.speed = speed
end

return {
    update_lastproj = update_lastproj,
    add_recent_file = add_recent_file,
    update_camera_setting = update_camera_setting,
    setting = editor_setting,
    save = save,
}