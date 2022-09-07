local utils = {}
local function do_deep_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[do_deep_copy(orig_key)] = do_deep_copy(orig_value)
        end
        setmetatable(copy, do_deep_copy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
function utils.deep_copy(orig)
    return do_deep_copy(orig)
end

function utils.time2str(time)
    local fmt = "%Y-%m-%d %H:%M:%S:"
    local ti, tf = math.modf(time)
    return os.date(fmt, ti)..string.format("%03d",math.floor(tf*1000))
end

local fs = require "filesystem"
local lfs = require "filesystem.local"

function utils.write_file(filename, data)
    local f
    if string.sub(filename, 1, 1) == "/" then
        local filepath = fs.path(filename)
        local name = filepath:filename()
        local path = filepath:remove_filename()
        f = assert(lfs.open(path:localpath() / name:string(), "wb"))
    else
        f = assert(lfs.open(fs.path(filename), "wb"))
    end
    f:write(data)
    f:close()
end

local datalist  = require "datalist"
function utils.readtable(filename)
    local path = fs.path(filename):localpath()
    local f = assert(lfs.open(path))
	local data = f:read "a"
	f:close()
    return datalist.parse(data)
end

function utils.class(classname, ...)
    local cls = {__cname = classname}
    local supers = {...}
    for _, super in ipairs(supers) do
        local superType = type(super)
        if superType == "table" then
            cls.__supers = cls.__supers or {}
            cls.__supers[#cls.__supers + 1] = super
            if not cls.super then
                cls.super = super
            end
        end
    end
    cls.__index = cls
    local mt
    if not cls.__supers or #cls.__supers == 1 then
        mt = {__index = cls.super}
    else
        mt = {__index = function(_, key)
                            local supers = cls.__supers
                            for i = 1, #supers do
                                local super = supers[i]
                                if super[key] then return super[key] end
                            end
                        end}
    end
    mt.__call = function(cls, ...)
        local instance = setmetatable({}, cls)
        instance.class = cls
        instance:_init(...)
        return instance
    end
    setmetatable(cls, mt)
    return cls
end

function utils.start_with(str, start)
    return str:sub(1, #start) == start
end
 
function utils.end_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
end

function utils.table_to_string(obj, cnt)
    local str = ""
    local cnt = cnt or 0
    if type(obj) == "table" then
        str = str .. "\n" .. string.rep("    ", cnt) .. "{\n"
        cnt = cnt + 1
        for k,v in pairs(obj) do
            if type(k) == "string" then
                str = str .. string.rep("    ",cnt) .. '["'..k..'"]' .. ' = '
            end
            if type(k) == "number" then
                str = str .. string.rep("    ",cnt) .. "["..k.."]" .. " = "
            end
            str = str .. utils.table_to_string(v, cnt)
            str = str .. ",\n"
        end
        cnt = cnt-1
        str = str .. string.rep("    ", cnt) .. "}"
    elseif type(obj) == "string" then
        str = str .. string.format("%q", obj)
    else
        str = str .. tostring(obj)
    end 
    return str
end

return utils