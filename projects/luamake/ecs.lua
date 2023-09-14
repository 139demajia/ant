local argn = select("#", ...)
if argn < 2 then
    print [[
at least 2 argument:
ecs.lua component.h package1, package2, ...
package1 and package2 are path to find *.ecs file
    ]]
    return
end
local component_h = select(1, ...)
local packages = {}
for i = 2, select('#', ...) do
    packages[i-1] = select(i, ...)
end

local fs = require "bee.filesystem"

local function createEnv(class)
    local function dummy()
        return function ()
            local o = {}
            local mt = {}
            function mt:__index()
                return function ()
                    return o
                end
            end
            return setmetatable(o, mt)
        end
    end
    local function object(object_name)
        local c = {}
        class[object_name] = c
        return function (name)
            local cc = {}
            c[name] = cc

            local o = {}
            local mt = {}
            function mt:__index(key)
                return function (value)
                    if cc[key] then
                        table.insert(cc[key], value)
                    else
                        cc[key] = {value}
                    end
                    return o
                end
            end
            return setmetatable(o, mt)
        end
    end
    return {
        import = function() end,
        feature = dummy(),
        pipeline = dummy(),
        system = dummy(),
        policy = dummy(),
        interface = dummy(),
        component = object "component",
    }
end

local function loadComponents()
    local class = {}
    local env = createEnv(class)
    local function eval(filename)
        assert(loadfile(filename:string(), "t", env))()
    end
    for _, pkgs in ipairs(packages) do
        for pkg in fs.pairs(pkgs) do
            for file in fs.pairs(pkg, "r") do
                if file:equal_extension "ecs" then
                    eval(file)
                end
            end
        end
    end

    local components = {}
    for name, info in pairs(class.component) do
        if not info.type then
            components[#components+1] = {name, "tag"}
        else
            local t = info.type[1]
            if t == "lua" then
            elseif t == "c" then
                components[#components+1] = {name, "c", info.field}
            elseif t == "raw" then
                components[#components+1] = {name, "raw", info.field[1], info.size[1]}
            else
                components[#components+1] = {name, t}
            end
        end
    end
    table.sort(components, function (a, b)
        return a[1] < b[1]
    end)
    return components
end

local components = loadComponents()


local out = {}

local function writefile(filename)
    local f <close> = assert(io.open(filename, "w"))
    f:write(table.concat(out, "\n"))
    out = {}
end

local function write(line)
    out[#out+1] = line
end

local TYPENAMES <const> = {
    int = "int32_t",
    int64 = "int64_t",
    dword = "uint32_t",
    word = "uint16_t",
    byte = "uint8_t",
    float = "float",
    userdata = "int64_t",
}

local function typenames(v)
    local _, ud = v:match "^([^|]+)|(.*)$"
    if ud then
        return ud
    end
    return assert(TYPENAMES[v], ("Invalid %s"):format(v))
end

do
    write "#pragma once"
    write ""
    write "#include \"ecs/select.h\""
    write "#include \"ecs/component_name.h\""
    write "#include \"ecs/user.h\""
    write "#include <stdint.h>"
    write "#include <array>"
    write "#include <string_view>"
    write ""
    write "namespace ant_ecs {"
    write ""
    write "using eid = uint64_t;"
    write "struct REMOVED {};"
    write ""
    for _, info in ipairs(components) do
        local name, type = info[1], info[2]
        if type == "c" then
            local fields = info[3]
            write(("struct %s {"):format(name))
            for _, field in ipairs(fields) do
                local name, typename = field:match "^([%w_]+):(.+)$"
                write(("\t%s %s;"):format(typenames(typename), name))
            end
            write("};")
            write ""
        elseif type == "raw" then
            local field, size = info[3], info[4]
            write(("struct %s {"):format(name))
            write(field:match "^(.-)[ \t\r\n]*$")
            write("};")
            write(("static_assert(sizeof(%s) == %s);"):format(name, size))
            write ""
        elseif type == "tag" then
            write(("struct %s {};"):format(name))
            write ""
        elseif type == "lua" then
            write(("struct %s {};"):format(name))
            write ""
        else
            write(("using %s = %s;"):format(name, typenames(type)))
            write ""
        end
    end
    
    write ""
    write "namespace decl {"
    write "struct component {"
    write "    std::string_view name;"
    write "    size_t           size;"
    write "};"
    write "template <typename T>"
    write "constexpr auto create() {"
    write "    return component {"
    write "        ecs_api::component_name_v<T>,"
    write "        std::is_empty_v<T> ? 0 : sizeof(T),"
    write "    };"
    write "}"
    write(("static constexpr std::array<component, %d> components = {"):format(#components))
    for _, c in ipairs(components) do
        write(("    create<%s>(),"):format(c[1]))
    end
    write "};"
    write ""
    write "}"
    write "}"
    write ""
    write "namespace ecs = ant_ecs;"
    write ""
    
    write "template <> constexpr inline int ecs_api::component_id<ecs::eid> = 0xFFFFFFFF;"
    write "template <> constexpr inline int ecs_api::component_id<ecs::REMOVED> = 0;"
    write ""
    write "#define ECS_COMPONENT(NAME, ID) \\"
    write "template <> constexpr inline int ecs_api::component_id<ecs::NAME> = ID;"
    write ""
    for i, c in ipairs(components) do
        write(("ECS_COMPONENT(%s,%d)"):format(c[1], i))
    end
    write ""
    write "#undef ECS_COMPONENT"
    write ""

    writefile(component_h .. "/component.hpp")
end
