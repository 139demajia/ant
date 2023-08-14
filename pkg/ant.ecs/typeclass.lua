local interface = require "interface"
local pm = require "packagemanager"
local serialization = require "bee.serialization"
local create_ecs = require "ecs"

local function splitname(fullname)
    return fullname:match "^([^|]*)|(.*)$"
end

local OBJECT = {"system","policy","component"}

local function solve_object(o, w, what, fullname)
	local decl = w._decl[what][fullname]
	if decl and decl.method then
		for _, name in ipairs(decl.method) do
			if not o[name] then
				error(("`%s`'s `%s` method is not defined."):format(fullname, name))
			end
		end
	end
end

local function solve_policy(fullname, v)
	local _, policy_name = splitname(fullname)
	local name = policy_name:match "^([%a_][%w_]*)$"
	if not name then
		error(("invalid policy name: `%s`."):format(policy_name))
	end
end

local check_map = {
	require_system = "system",
	require_policy = "policy",
	require_transform = "transform",
	component = "component",
	component_opt = "component",
}

local copy = {}
function copy.policy(v)
	return {
		policy = v.require_policy,
		component = v.component,
		component_opt = v.component_opt,
	}
end
function copy.component(v)
	return {}
end
function copy.system() return {} end

local function create_importor(w)
	local declaration = w._decl
	local import = {}
    for _, objname in ipairs(OBJECT) do
		local class = {}
		w._class[objname] = class
		import[objname] = function (name)
			local v = class[name]
            if v then
                return v
			end
			if not w._initializing and objname == "system" then
                error(("system `%s` can only be imported during initialization."):format(name))
			end
            local v = declaration[objname][name]
			if not v then
                error(("invalid %s name: `%s`."):format(objname, name))
            end
			log.debug("Import  ", objname, name)
			local res = copy[objname](v)
			class[name] = res
			for _, tuple in ipairs(v.value) do
				local what, k = tuple[1], tuple[2]
				local attrib = check_map[what]
				if attrib then
					import[attrib](k)
				end
			end
			if objname == "policy" then
				solve_policy(name, res)
			end
			if v.implement and v.implement[1] then
				local impl = v.implement[1]
				if impl:sub(1,1) == ":" then
					v.c = true
					w._class.system[name] = w:clibs(impl:sub(2))
				else
					local pkg = v.packname
					local file = impl
									:gsub("^(.*)%.lua$", "%1")
									:gsub("/", ".")
					w._ecs[pkg].include_ecs(file)
				end
			end
			return res
		end
	end
	return import
end

local function import_decl(w, fullname)
	local packname, filename
	assert(fullname:sub(1,1) == "@")
	if fullname:find "/" then
		packname, filename = fullname:match "^@([^/]*)/(.*)$"
	else
		packname = fullname:sub(2)
		filename = "package.ecs"
	end
	w._decl:load(packname, filename)
	w._decl:check()
end

local function toint(v)
	local t = type(v)
	if t == "userdata" then
		local s = tostring(v)
		s = s:match "^%a+: (%x+)$" or s:match "^%a+: 0x(%x+)$"
		return tonumber(assert(s), 16)
	end
	if t == "number" then
		return v
	end
	assert(false)
end

local function cstruct(...)
	local ref = table.pack(...)
	local t = {}
	for i = 1, ref.n do
		t[i] = toint(ref[i])
	end
	return string.pack("<"..("T"):rep(ref.n), table.unpack(t))
		, ref
end

local function create_context(w)
	local bgfx       = require "bgfx"
	local math3d     = require "math3d"
	local components = require "ecs.components"
	local ecs = w.w
	local component_decl = w._component_decl
	local function register_component(i, decl)
		local id, size = ecs:register(decl)
		assert(id == i)
		assert(size == components[decl.name] or 0)
	end
	for i, name in ipairs(components) do
		local decl = component_decl[name]
		if decl then
			component_decl[name] = nil
			register_component(i, decl)
		else
			local csize = components[name]
			if csize then
				register_component(i, {
					name = name,
					type = "raw",
					size = csize
				})
			else
				register_component(i, { name = name })
			end
		end
	end
	for _, decl in pairs(component_decl) do
		ecs:register(decl)
	end
	w._component_decl = nil
	local ecs_context = ecs:context()
	w._ecs_world,
	w._ecs_ref = cstruct(
		ecs_context,
		bgfx.CINTERFACE,
		math3d.CINTERFACE,
		bgfx.encoder_get(),
		0,0,0,0 --kMaxMember == 4
	)
end

local function update_decl(world)
    world._component_decl = {}
    local function register_component(decl)
        world._component_decl[decl.name] = decl
    end
    local component_class = world._class.component
    for name, info in pairs(world._decl.component) do
        local type = info.type[1]
        local class = component_class[name] or {}
        if type == "lua" then
            register_component {
                name = name,
                type = "lua",
                init = class.init,
                marshal = class.marshal or serialization.packstring,
                demarshal = class.demarshal or nil,
                unmarshal = class.unmarshal or serialization.unpack,
            }
        elseif type == "c" then
            local t = {
                name = name,
                init = class.init,
                marshal = class.marshal,
                demarshal = class.demarshal,
                unmarshal = class.unmarshal,
            }
            for i, v in ipairs(info.field) do
                t[i] = v:match "^(.*)|.*$" or v
            end
            register_component(t)
        elseif type == "raw" then
            local t = {
                name = name,
                type = "raw",
                size = assert(math.tointeger(info.size[1])),
                init = class.init,
                marshal = class.marshal,
                demarshal = class.demarshal,
                unmarshal = class.unmarshal,
            }
            register_component(t)
        elseif type == nil then
            register_component {
                name = name
            }
        else
            register_component {
                name = name,
                type = type,
            }
        end
    end
end

local function init(w, config)
	w._initializing = true
	w._class = {}
	w._decl = interface.new(function(_, packname, filename)
		local file = "/pkg/"..packname.."/"..filename
		log.debug(("Import decl %q"):format(file))
		return assert(pm.loadenv(packname).loadfile(file))
	end)
	w._importor = create_importor(w)
	function w:_import(objname, name)
		local res = w._class[objname][name]
		if res then
			return res
		end
		res = w._importor[objname](name)
		if res then
			solve_object(res, w, objname, name)
		end
		return res
	end
	setmetatable(w._ecs, {__index = function (_, package)
		return create_ecs(w, package)
	end})

	config.ecs = config.ecs or {}
	if config.ecs.import then
		for _, k in ipairs(config.ecs.import) do
			import_decl(w, k)
		end
	end
	local import = w._importor
	for _, objname in ipairs(OBJECT) do
		if config.ecs[objname] then
			for _, k in ipairs(config.ecs[objname]) do
				import[objname](k)
			end
		end
	end
	update_decl(w)
	w._initializing = false

    for _, objname in ipairs(OBJECT) do
		for fullname, o in pairs(w._class[objname]) do
			solve_object(o, w, objname, fullname)
        end
    end
	create_context(w)
end

return {
	init = init,
}
