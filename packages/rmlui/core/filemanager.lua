local fs = require "filesystem"

local cr = import_package "ant.compile_resource"
local lfont = require "font"

cr.init()

local m = {}

local directorys  = { fs.path "/" }

local function import_font(path)
    for p in fs.pairs(path) do
        if fs.is_directory(p) then
            import_font(p)
        elseif fs.is_regular_file(p) then
            if p:equal_extension "otf" or p:equal_extension "ttf" or p:equal_extension "ttc" then
                lfont.import(p:string())
            end
        end
    end
end

function m.font_dir(dir)
    import_font(fs.path(dir))
end

function m.preload_dir(dir)
    directorys[#directorys+1] = fs.path(dir)
end

function m.vfspath(path)
    for i = #directorys, 1, -1 do
        local file = directorys[i] / path
        if fs.exists(file) then
            if file:equal_extension "texture" or file:equal_extension "png" then
                return
            end
            return file:string()
        end
    end
end

local function find_texture(path)
    for i = #directorys, 1, -1 do
        local file = directorys[i] / path
        if fs.exists(file) then
            return cr.compile(file:string() .. "|main.bin"):string()
        end
    end
end

function m.realpath(path)
    if fs.path(path):equal_extension "texture" or fs.path(path):equal_extension "png" then
        return find_texture(path)
    end
    for i = #directorys, 1, -1 do
        local file = directorys[i] / path
        if fs.exists(file) then
            return file:localpath():string()
        end
    end
end

function m.exists(path)
    for i = #directorys, 1, -1 do
        local file = directorys[i] / path
        if fs.exists(file) then
            return true
        end
    end
end

return m
