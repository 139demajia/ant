local resource = import_package "ant.resource"

local function sortpairs(t)
    local sort = {}
    for k in pairs(t) do
        sort[#sort+1] = k
    end
    table.sort(sort)
    local n = 1
    return function ()
        local k = sort[n]
        if k == nil then
            return
        end
        n = n + 1
        return k, t[k]
    end
end

local w
local disableSerialize
local path
local typeinfo
local foreach_init_1

local poppath = setmetatable({}, {__close=function() path[#path] = nil end})
local function pushpath(v)
    path[#path+1] = v
    return poppath
end

local function create_proxy(filename)
    resource.load(filename, nil, true)
    return resource.proxy(filename)
end

local function foreach_init_2(c, args)
    if c.type == 'primtype' then
        assert(args ~= nil)
        return args
    end
    if c.type == 'entityid' then
        if disableSerialize then
            assert(type(args) == "number")
            return args
        else
            assert(type(args) == "string")
            return w:find_entity(args) or args
        end
    end
    local ti = typeinfo[c.type]
    assert(ti, "unknown type:" .. c.type)
    if c.array then
        local n = c.array == 0 and (args and #args or 0) or c.array
        local res = {}
        for i = 1, n do
            local _ <close> = pushpath(i)
            res[i] = foreach_init_1(ti, args[i])
        end
        return res
    end
    if c.map then
        local res = {}
        if args then
            for k, v in sortpairs(args) do
                if type(k) == "string" then
                    local _ <close> = pushpath(k)
                    res[k] = foreach_init_1(ti, v)
                end
            end
        end
        return res
    end
    return foreach_init_1(ti, args)
end

function foreach_init_1(c, args)
    if c.type == 'tag' then
        assert(args == true or args == nil)
        return args
    end

    local ret
    if c.resource then
        ret = create_proxy(args)
    elseif c.type then
        ret = foreach_init_2(c, args)
    else
        ret = {}
        for _, v in ipairs(c) do
            if args[v.name] == nil and v.attrib and v.attrib.opt then
                goto continue
            end
            assert(v.type)
            local _ <close> = pushpath(v.name)
            ret[v.name] = foreach_init_2(v, args[v.name])
            ::continue::
        end
    end
    if c.method and c.method.init then
        ret = c.method.init(ret)
    end
    return ret
end

local function init(w_, c, args, disableSerialize_)
    w = w_
    disableSerialize = disableSerialize_
    typeinfo = w._class.component
    path = {}
    local _ <close> = pushpath(c.name)
    return foreach_init_1(c, args)
end

local foreach_delete_1
local function foreach_delete_2(c, component)
    if c.type == 'primtype' then
        return
    end
    assert(typeinfo[c.type], "unknown type:" .. c.type)
    foreach_delete_1(typeinfo[c.type], component)
end

function foreach_delete_1(c, component, e)
    if c.method and c.method.delete then
        component = c.method.delete(component, e) or component
    end
    if not c.type then
        for _, v in ipairs(c) do
            if component[v.name] == nil and v.attrib and v.attrib.opt then
                goto continue
            end
            assert(v.type)
            foreach_delete_1(v, component[v.name])
            ::continue::
        end
        return
    end
    if c.array then
        local n = c.array == 0 and #component or c.array
        for i = 1, n do
            foreach_delete_2(c, component[i])
        end
        return
    end
    if c.map then
        for k, v in pairs(component) do
            if type(k) == "string" then
                foreach_delete_2(c, v)
            end
        end
        return
    end
    foreach_delete_2(c, component)
end

local function delete(w_, c, component, e)
    w = w_
    typeinfo = w._class.component
    return foreach_delete_1(c, component, e)
end

local function gen_ref(c)
    if c.ref ~= nil then
        return c.ref
    end
    if not c.type then
        c.ref = true
        for _,v in ipairs(c) do
            v.ref = gen_ref(v)
        end
        return c.ref
    end
    if c.type == 'primtype' then
        c.ref = false
        return c.ref
    end
    assert(typeinfo[c.type], "unknown type:" .. c.type)
    c.ref = gen_ref(typeinfo[c.type])
    return c.ref
end

local function solve(schema)
    typeinfo = schema.map
    for _,v in ipairs(schema.list) do
        if v.uncomplete then
            error(v.name .. " is uncomplete")
        end
    end
    for k in pairs(schema._undefined) do
        if not schema.map[k] then
            error(k .. " is undefined in " .. schema._undefined[k])
        end
    end
    for _,v in pairs(schema.map) do
        gen_ref(v)
    end
end

return {
    init = init,
    delete = delete,
    solve = solve,
}
