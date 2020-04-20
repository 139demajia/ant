local typeclass = require "typeclass"

local function splitname(fullname)
    return fullname:match "^([^|]*)|(.*)$"
end

local function create(w, policies)
    local policy_class = w._class.policy
    local transform_class = w._class.transform
    local solve_depend = require "solve_depend"
    local transform = {}
    local component = {}
    local init_component = {}
    local policyset = {}
    local unionset = {}
    for _, name in ipairs(policies) do
        local class = policy_class[name]
        if not class then
            typeclass.import_object(w, "policy", name)
            class = policy_class[name]
            if not class then
                error(("policy `%s` is not defined."):format(name))
            end
        end
        if policyset[name] then
            goto continue
        end
        policyset[name] = name
        if class.union then
            if unionset[class.union] then
                error(("duplicate union `%s` in `%s` and `%s`."):format(class.union, name, unionset[class.union]))
            end
            unionset[class.union] = name
        end
        for _, v in ipairs(class.require_transform) do
            if not transform[v] then
                transform[v] = {}
            end
        end
        for _, v in ipairs(class.require_component) do
            if not component[v] then
                component[v] = {depend={}}
                init_component[#init_component+1] = v
            end
        end
        for _, v in ipairs(class.unique_component) do
            if not component[v] then
                component[v] = {depend={}}
                init_component[#init_component+1] = v
            end
        end
        ::continue::
    end
    local function table_append(t, a)
        table.move(a, 1, #a, #t+1, t)
    end
    local reflection = {}
    for name in pairs(transform) do
        local class = transform_class[name]
        for _, v in ipairs(class.output) do
            if reflection[v] then
                error(("transform `%s` and transform `%s` has same output."):format(name, reflection[v]))
            end
            reflection[v] = name
            if class.input then
                table_append(component[v].depend, class.input)
            end
        end
    end
    local mark = {}
    local init_transform = {}
    for _, c in ipairs(solve_depend(component)) do
        local name = reflection[c]
        if name and not mark[name] then
            mark[name] = true
            init_transform[#init_transform+1] = transform_class[name].methodfunc.process
        end
    end
    table.sort(init_component)
    return init_component, init_transform
end

local function add(w, eid, policies)
    local component, transform = create(w, policies)
    local e = w[eid]
    local policy_class = w._class.policy
    local transform_class = w._class.transform
    for _, policy_name in ipairs(policies) do
        local class = policy_class[policy_name]
        for _, transform_name in ipairs(class.require_transform) do
            local class = transform_class[transform_name]
            for _, v in ipairs(class.output) do
                if e[v] ~= nil then
                    error(("component `%s` already exists, it conflicts with policy `%s`."):format(v, policy_name))
                end
            end
        end
    end
    local i = 1
    while i <= #component do
        local c = component[i]
        if e[c] ~= nil then
            table.remove(component, i)
        else
            i = i + 1
        end
    end
    return component, transform
end

local function solve(w)
    local class = w._class
    for fullname, v in pairs(class.transform) do
        local _, name = splitname(fullname)
        if #v.output == 0 then
            error(("transform `%s`'s output cannot be empty."):format(name))
        end
        if type(v.methodfunc.process) ~= 'function' then
            error(("transform `%s`'s process cannot be empty."):format(name))
        end
    end
    for fullname, v in pairs(class.policy) do
        local _, policy_name = splitname(fullname)
        local union_name, name = policy_name:match "^([%a_][%w_]*)%.([%a_][%w_]*)$"
        if not union_name then
            name = policy_name:match "^([%a_][%w_]*)$"
        end
        if not name then
            error(("invalid policy name: `%s`."):format(policy_name))
        end
        v.union = union_name
        local components = {}
        if not v.require_component and not v.unique_component then
            error(("policy `%s`'s require_component or unique_component cannot be empty."):format(policy_name))
        end
        if not v.require_component then
            v.require_component = {}
        end
        if not v.unique_component then
            v.unique_component = {}
        end
        if not v.require_transform then
            v.require_transform = {}
        end
        for _, component_name in ipairs(v.require_component) do
            if not class.component[component_name] then
                error(("component `%s` in policy `%s` is not defined."):format(component_name, policy_name))
            end
            components[component_name] = true
        end
        for _, component_name in ipairs(v.unique_component) do
            if not class.component[component_name] then
                error(("component `%s` in policy `%s` is not defined."):format(component_name, policy_name))
            end
            components[component_name] = true
        end
        for _, transform_name in ipairs(v.require_transform) do
            local c = class.transform[transform_name]
            if not c then
                error(("transform `%s` in policy `%s` is not defined."):format(transform_name, policy_name))
            end
            if c.input then
                for _, v in ipairs(c.input) do
                    if not components[v] then
                        error(("transform `%s` requires component `%s`, but policy `%s` does not requires it."):format(transform_name, v,   policy_name))
                    end
                end
            end
            for _, v in ipairs(c.output) do
                if not components[v] then
                    error(("transform `%s` requires component `%s`, but policy `%s` does not requires it."):format(transform_name, v, policy_name)  )
                end
            end
        end
    end
end

return {
    create = create,
    add = add,
    solve = solve,
}
