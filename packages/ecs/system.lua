local system = {}

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

local function table_append(t, a)
	table.move(a, 1, #a, #t+1, t)
end

local function solve_depend(res, step, pipeline)
	for _, v in ipairs(pipeline) do
		if type(v) == "string" then
			if step[v] == false then
				error(("pipeline has duplicate step `%s`"):format(v))
			elseif step[v] ~= nil then
				table_append(res, step[v])
				step[v] = false
			end
		elseif type(v) == "table" and v.value then
			solve_depend(res, step, v.value)
		end
	end
end

function system.init(sys, pipeline)
	local mark = {}
	local res = setmetatable({}, {__index = function(t,k)
		local obj = {}
		t[k] = obj
		mark[k] = true
		return obj
	end})
	for pkg_name, pkg_system in sortpairs(sys) do
		for sys_name, s in sortpairs(pkg_system) do
			local proxy = {}
			for step_name, func in pairs(s.method) do
				table.insert(res[step_name], { func, proxy, sys_name, step_name, pkg_name })
			end
		end
	end
	setmetatable(res, nil)

	for _, pl in pairs(pipeline) do
		if pl.value then
			for _, v in ipairs(pl.value) do
				if type(v) == "string" then
					mark[v] = nil
				end
			end
		end
	end

	for name in pairs(mark) do
		error(("pipeline is missing step `%s`, which is defined in system `%s`"):format(name, res[name][1][1]))
	end
	return {
		steps = res,
		pipeline = pipeline,
	}
end

function system.lists(sys, what)
	local pl = sys.pipeline[what]
	if not pl or not pl.value then
		return
	end
	local res = {}
	solve_depend(res, sys.steps, pl.value)
	return res
end

local switch_mt = {}; switch_mt.__index = switch_mt

function switch_mt:enable(name, enable)
	if enable ~= false then
		enable = nil
	end
	if self[name] ~= enable then
		self.__needupdate = true
		self[name] = enable
	end
end

function switch_mt:update()
	if self.__needupdate then
		local index = 1
		local all = self.__all
		local list = self.__list
		for i = 1, #all do
			local name = all[i][5] .. "|" .. all[i][3]
			if self[name] ~= false then
				-- enable it
				list[index] = all[i]
				index = index + 1
			end
		end
		for i = index, #list do
			list[i] = nil
		end
		self.__needupdate = nil
	end
end

function system.list_switch(list)
	local all_list = {}
	for k,v in pairs(list) do
		all_list[k] = v
	end
	return setmetatable({
		__list = list,
		__all = all_list,
	} , switch_mt )
end

return system
