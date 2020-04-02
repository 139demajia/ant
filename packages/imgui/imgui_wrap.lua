local fs = require "filesystem"
local bgfx = require "bgfx"
local EnableLuaWrap = true --main switch
local EnableLuaTrace = false
local EnableCheckPair = true
local EnabelFlagsWrap = true

-- local log = print

--log error when tryint to index a unexist key
local function asset_index(tbl,path)
    return function( _,key )
        local v = tbl[key]
        if v then
            return v
        else
        log(string.format("[Imgui Error]:%s<%s> not exist!",path,key))
            log(debug.traceback())
        end
    end
end

local function wrap_table(tbl,path)
    path = path and (path..".") or ""
    local result = {}
    result = setmetatable(result,{__index = asset_index(tbl,path)})
    for k,v in pairs(tbl) do
        if type(v) == "table" then
            result[k] = wrap_table(v,path..k)
        end
    end
    return result
end

--make flags.flagA.KeyA <=> flags.flagA({KeyA})
local function wrap_flags(flags_c,flags)
    for fname,_ in pairs(flags_c) do
        local fun = flags[fname]
        local mt = {}
        mt.__call = function(self,arr)
            return fun(arr)
        end
        mt.__index = function(self,k)
            return fun({k})
        end
        flags[fname] = setmetatable({},mt)
    end
end

local imgui_c = require "imgui.ant"
local widget_c = imgui_c.widget
local flags_c = imgui_c.flags
local windows_c = imgui_c.windows
local util_c = imgui_c.util
local cursor_c = imgui_c.cursor
local enum_c = imgui_c.enum
local imgui_lua = setmetatable({},{__index=imgui_c})
imgui_lua.widget = setmetatable({},{__index=widget_c})
imgui_lua.flags = setmetatable({},{__index=flags_c})
imgui_lua.windows = setmetatable({},{__index=windows_c})
imgui_lua.util = setmetatable({},{__index=util_c})
imgui_lua.cursor = setmetatable({},{__index=cursor_c})
imgui_lua.enum = wrap_table(enum_c,"imgui.enum")

local function trace_call(src,dst,name)
    for k,v in pairs(src) do
        if type(v) == "function" then
            local f = dst[k]
            local function w(...)
                log(string.format("call function %s.%s",name, k),...)
                return f(...)
            end
            dst[k] = w
        end
    end
end

--todo
local handle_cache = {}
--path:"/pkg/ant.resources.binary/textures/PVPScene/BH-Scene-Tent-d.dds"
local function path2tex_handle(path)
    if type(path) == "string" then
        if not handle_cache[path] then
            local fs = require "filesystem"
            local assetmgr = import_package "ant.asset"
            local loader = assetmgr.get_loader "texture"
            local t = loader(fs.path(path) )
            log.info_a("load",path,t)
            -- local texrefpath = fs.path(path)
            -- local f = assert(fs.open(texrefpath, "rb"))
            -- local imgdata = f:read "a"
            -- f:close()
            -- handle_cache[path] = bgfx.create_texture(imgdata, "")
            handle_cache[path] = t.handle
        end
        return handle_cache[path]
    else
        return path
    end
end

function imgui_lua.widget.Image(...)
    local args = {...}
    if type(args[1]) == "string" then
        args[1] = path2tex_handle(args[1])
    end
    return widget_c.Image(table.unpack(args))
end

function imgui_lua.widget.ImageButton(...)
    local args = {...}
    if type(args[1]) == "string" then
        args[1] = path2tex_handle(args[1])
    end
    return widget_c.ImageButton(table.unpack(args))
end

if EnableLuaTrace then
    trace_call(imgui_c,imgui_lua,"imgui")
    trace_call(widget_c,imgui_lua.widget,"imgui.widget")
    trace_call(flags_c,imgui_lua.flags,"imgui.flags")
    trace_call(windows_c,imgui_lua.windows,"imgui.windows")
    trace_call(util_c,imgui_lua.util,"imgui.util")
    trace_call(cursor_c,imgui_lua.cursor,"imgui.cursor")
end

if EnabelFlagsWrap then
    wrap_flags(flags_c,imgui_lua.flags)
end

if EnableCheckPair then
    local check_pairs = require "imgui_check_pairs"
    check_pairs(imgui_lua)
end


if EnableLuaWrap then
    return imgui_lua
else
    return imgui_c
end
