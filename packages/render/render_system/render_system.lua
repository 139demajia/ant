local ecs = ...
local world = ecs.world
local w = world.w

local bgfx 		= require "bgfx"
local math3d 	= require "math3d"
local irender	= ecs.import.interface "ant.render|irender"
local ies		= ecs.import.interface "ant.scene|ifilter_state"
local imaterial = ecs.import.interface "ant.asset|imaterial"
local itimer	= ecs.import.interface "ant.timer|itimer"
local igroup	= ecs.import.interface "ant.render|igroup"
local render_sys = ecs.system "render_system"

local viewidmgr = require "viewid_mgr"
for n, b in pairs(viewidmgr.all_bindings()) do
	for viewid=b[1], b[1]+b[2]-1 do
		bgfx.set_view_name(viewid, n .. "_" .. viewid)
	end
end

function render_sys:component_init()
	for e in w:select "INIT render_object:update filter_material:out render_object_update?out" do
		e.render_object = e.render_object or {}
		e.filter_material = {}
		e.render_object_update = true
	end
end

function render_sys:entity_init()
	w:clear "filter_created"
	for qe in w:select "INIT primitive_filter:in queue_name:in filter_created?out" do
		local pf = qe.primitive_filter
		local qn = qe.queue_name
		for i=1, #pf do
			local n = qn .. "_" .. pf[i]
			pf[i] = n
			w:register{name = n}
		end

		qe.filter_created = true
		w:sync("filter_created?out", qe)

		pf._DEBUG_filter_type = pf.filter_type
		pf.filter_type = ies.filter_mask(pf.filter_type)
		pf._DEBUG_excule_type = pf.exclude_type
		pf.exclude_type = pf.exclude_type and ies.filter_mask(pf.exclude_type) or 0
	end

	for e in w:select "INIT material_result:in scene:in render_object:in" do
		local ro = e.render_object
		local mr = e.material_result
		ro.material = mr.object:instance()
        ro.fx     	= mr.fx
		
		ro.worldmat = e.scene.worldmat
	end
end

local time_param = math3d.ref(math3d.vector(0.0, 0.0, 0.0, 0.0))
local starttime = itimer.current()
local timepassed = 0.0
local function update_timer_param()
	local sa = imaterial.system_attribs()
	timepassed = timepassed + itimer.delta()
	time_param.v = math3d.set_index(time_param, 1, timepassed*0.001, itimer.delta()*0.001)
	sa:update("u_time", time_param)
end

function render_sys:commit_system_properties()
	update_timer_param()
end

local function has_filter_tag(t, filter)
	for _, fn in ipairs(filter) do
		if fn == t then
			return true
		end
	end
end

function render_sys:update_filter()
	w:clear "filter_result"
    for e in w:select "render_object_update render_object:in filter_result:new" do
        local ro = e.render_object
        local filterstate = ro.filter_state
		local st = ro.fx.setting.surfacetype

		local filter_result = {}
		for qe in w:select "queue_name:in primitive_filter:in" do
			local qn = qe.queue_name
			local tag = ("%s_%s"):format(qn, st)

			local pf = qe.primitive_filter
			if has_filter_tag(tag, pf) then
				w:sync(tag .. "?in", e)
				local add = ((filterstate & pf.filter_type) ~= 0) and ((filterstate & pf.exclude_type) == 0)
				if add then
					if not e[tag] then
						filter_result[tag] = add
						e[tag] = add
						w:sync(tag .. "?out", e)
					end
				else
					if e[tag] then
						filter_result[tag] = add
						e[tag] = add
						w:sync(tag .. "?out", e)
					end
				end
			end
		end
		e.filter_result = filter_result
    end
end

local function submit_render_objects(viewid, filter, culltag)
	for idx, fn in ipairs(filter) do
		local s = culltag and
			("view_visible %s %s:absent render_object:in filter_material:in"):format(fn, culltag[idx]) or
			("view_visible %s render_object:in filter_material:in"):format(fn)

		for e in w:select(s) do
			irender.draw(viewid, e.render_object, e.filter_material[fn])
		end
	end
end

function render_sys:render_submit()
	for qe in w:select "visible camera_ref:in render_target:in primitive_filter:in cull_tag?in" do
		local camera = world:entity(qe.camera_ref).camera
		local rt = qe.render_target
		local viewid = rt.viewid

		bgfx.touch(viewid)
		bgfx.set_view_transform(viewid, camera.viewmat, camera.projmat)
		submit_render_objects(viewid, qe.primitive_filter, qe.cull_tag)
    end
end

local s = ecs.system "end_filter_system"

local function check_set_depth_state_as_equal(state)
	local ss = bgfx.parse_state(state)
	ss.DEPTH_TEST = "EQUAL"
	local wm = ss.WRITE_MASK
	ss.WRITE_MASK = wm and wm:gsub("Z", "") or "RGBA"
	return bgfx.make_state(ss)
end

function s:end_filter()
	if irender.use_pre_depth() then
		for e in w:select "filter_result:in render_object:in" do
			local ro = e.render_object
			local rom = ro.material
			local fn = e.filter_result
			if fn["main_queue_opacity"] and ro.fx.setting.surfacetype == "opacity" then
				rom:get_material():set_state(check_set_depth_state_as_equal(rom:get_state()))
			end
		end
	end
	w:clear "render_object_update"
end