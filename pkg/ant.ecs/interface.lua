--[[
	ECS interface , written in .ecs file :

----- interface.ecs ---
import "filename.ecs"
implement "filename.lua"

system "system_name"
	.require_system "other_system"
	.require_system "packname|system_in_packname"
	.stage "stage_a"
	.stage "stage_b"

policy "policy_name"
	.require_system "system_name"

-----------------------

	Usage:

	local interface = require "interface"

	-- should returns a function
	local function loader(packname, filename)
		local f = loadfile(packname .. "/" .. filename)
		return f
	end

	local parser = interface.new(loader)

	parser:load(packname1, filename)
	parser:load(packname2, filename)
	parser:load(packname3, filename)
	...

	parser:check()
]]

local interface = {}
interface.__index = interface

local parser = {}

local attribute = {
	pipeline = {
		"pipeline",
		"stage",
	},
	system = {
		"implement",
		"require_system",
		"require_policy",
	},
	policy = {
		"require_system",
		"include_policy",
		"component",
		"component_opt",
	},
	component = {
		"implement",
		"require_system",
		"type",
		"size",
		"field",
	},
}

local no_packspace = {
	pipeline = true,
	none = true,
	component = true,
}

local check_map = {
	require_system = "system",
	require_policy = "policy",
	include_policy = "policy",
	component = "component",
	component_opt = "component",
	pipeline = "none",
	stage = "none",
}

local type_list = {}
local packspace_map = {}

do	-- init type_list
	for attrib in pairs(attribute) do
		table.insert(type_list, attrib)
	end

	for what, attrib in pairs(check_map) do
		if not no_packspace[attrib] then
			packspace_map[what] = true
		end
	end
end

function parser.new(loader)
	local p = {
		loaded = {},
		loader = loader,
	}
	for _, type in ipairs(type_list) do
		p[type] = {}
	end
	return setmetatable( p, interface )
end

local function insert_fileinfo(result)
	local item = result[#result]
	local info = debug.getinfo(3, "Sl")
	item.source = info.source
	item.lineno = info.currentline
end

local function readonly()
	error "_G is readonly"
end

local function fullname(packname, name)
	return packname .. "|" .. name
end

local function attribute_setter(attribs, packname, contents)
	local setter = {}

	for _, a in ipairs(attribs) do
		if packspace_map[a] then
			setter[a] = function(what)
				assert(type(what) == "string")
				if not what:find("|",1,true) then
					what = fullname(packname, what)
				end
				table.insert(contents, {a, what})
				return setter
			end
		else
			setter[a] = function(what)
				assert(type(what) == "string")
				table.insert(contents, {a, what})
				return setter
			end
		end
	end

	return setter
end

local load_interface do
	local genenv
	load_interface = function (self, current, packname, filename, result)
		if self.loaded[packname.."/"..filename] then
			return result
		end
		self.loaded[packname.."/"..filename] = true
		local f = self.loader(current, packname, filename)
		assert(debug.getupvalue(f,1) == "_ENV")
		debug.setupvalue(f,1,genenv(self, packname, result))
		f()
		return result
	end

	genenv = function (self, packname, result)
		local api = {}
		function api.import(filename)
			local pname, fname = packname, filename
			if filename:sub(1,1) == "@" then
				if filename:find "/" then
					pname, fname = filename:match "^@([^/]*)/(.*)$"
				else
					pname = filename:sub(2)
					fname = "package.ecs"
				end
			end
			load_interface(self, packname, pname, fname, result)
		end
		for _, attr in ipairs(type_list) do
			api[attr] = function (name)
				local contents = {}
				local setter = attribute_setter(attribute[attr], packname, contents)
				local fname = no_packspace[attr] and name or fullname(packname, name)
				table.insert(result, { command = attr, packname = packname, name = fname, value = contents })
				insert_fileinfo(result)
				return setter
			end
		end
		return setmetatable( {}, { __index = api , __newindex = readonly } )
	end
end

local function merge_all_results(results)
	local r = { implement = {} }
	for _, what in ipairs(type_list) do
		r[what] = {}
	end

	for _, item in ipairs(results) do
		local m = r[item.command]
		if item.name then
			if m[item.name] ~= nil then
				error(string.format("Redfined %s:%s in %s(%d), Already defined at %s(%d)",
					item.command, item.name, item.source, item.lineno, m[item.name].source, m[item.name].lineno))
			end
			m[item.name] = item
		else
			table.insert(m, item)
		end
	end
	return r
end

local function merge(output, input, list)
	for name, item in pairs(input) do
		local value = {
			packname = item.packname,
			value = {},
		}
		for _, attrib in ipairs(list) do
			value[attrib] = {}
		end
		output[name] = value
		for _, tuple in ipairs(item.value) do
			if check_map[tuple[1]] then
				table.insert(value.value, tuple)
			end
			table.insert(value[tuple[1]], tuple[2])
		end
	end
end

local function merge_result(self, result)
	for _, what in ipairs(type_list) do
		merge(self[what], result[what], attribute[what])
	end
end

function interface:load(packname, filename)
	--TODO
	local results = load_interface(self, nil, packname, filename, {})
	local r = merge_all_results(results)
	merge_result(self, r)
	return r
end

local function check(tbl, r)
	for _, content in pairs(tbl) do
		for what, list in pairs(content) do
			local check = check_map[what]
			if check and check ~= "none" then
				-- need check
				for _, require_name in ipairs(list) do
					if r[check][require_name] == nil then
						error(string.format("Not found (%s) : %s",check, require_name))
					end
				end
			end
		end
	end
end

function interface:check()
	for _, what in ipairs(type_list) do
		check(self[what], self)
	end
end

return parser
