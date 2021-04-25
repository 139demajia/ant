local ecs = ...
local world = ecs.world
local timer = world:interface "ant.timer|timer"
local fs 	= require "filesystem"
local lfs	= require "filesystem.local"
local datalist  = require "datalist"

local function get_transmit_merge(e, tt_duration)
	local timepassed = 0
	return function (deltatime)
		timepassed = timepassed + deltatime
		local current_pose = e._animation._current
		if timepassed > tt_duration then
			e._animation._current = current_pose[#current_pose]
			return true
		end
		local scale = math.max(0, math.min(1, timepassed / tt_duration))
		for i = 1, #current_pose-1 do
			current_pose[i].weight = current_pose[i].init_weight * (1 - scale)
		end
		current_pose[#current_pose].weight = scale
		return false
	end
end

local function current_animation(current)
	if current.type == 'blend' then
		return current[#current].animation
	else
		return current.animation
	end
end

local function play_animation(e, name, duration)
	local current_ani = current_animation(e._animation._current)
	if current_ani and current_ani.name == name then
		return
	end
	local current_pose = e._animation._current
	if current_pose.type == "blend" then
		for i = 1, #current_pose do
			current_pose[i].init_weight = current_pose[i].weight
		end
		local ani = e.animation[name]
		current_pose[#current_pose+1] = {
			animation = ani,
			weight = 0,
            ratio = 0,
		}
	elseif current_pose.animation then
		e._animation._current = {
			type = "blend",
			{
				animation = current_pose.animation,
				event_state = {
					next_index = 1,
					keyframe_events = current_pose.event_state
				},
				clip_state = { current = {clip_index = 1}, clips = e.anim_clips and e.anim_clips[name] or {}},
				weight = 1,
				init_weight = 1,
				ratio = current_pose.ratio,
			},
			{
				animation = e.animation[name],
				event_state = {
					next_index = 1,
					keyframe_events = e.keyframe_events and e.keyframe_events[name] or {}
				},
				clip_state = { current = {clip_index = 1}, clips = e.anim_clips and e.anim_clips[name] or {}},
				weight = 0,
				init_weight = 0,
				play_state = { ratio = 0.0, previous_ratio = 0.0, speed = 1.0, play = true, loop = true}
			}
		}
	else
		e._animation._current = {
			animation = e.animation[name],
			event_state = {
				next_index = 1,
				keyframe_events = e.keyframe_events and e.keyframe_events[name] or {}
			},
			clip_state = { current = {clip_index = 1}, clips = e.anim_clips and e.anim_clips[name] or {}},
			play_state = { ratio = 0.0, previous_ratio = 0.0, speed = 1.0, play = true, loop = true}
		}
		return
	end
	e.state_machine.transmit_merge = get_transmit_merge(e, duration * 1000.)
end

local function set_state(e, name, time)
	local sm = e.state_machine
	local info = sm.nodes[name]
	if info.execute then
		play_animation(e, info:execute(), time)
	else
		play_animation(e, name, time)
	end
	sm.current = name
end

local sm = ecs.component "state_machine"

function sm:init()
	if self.file then
		assert(fs.loadfile(fs.path(self.file)))(self.nodes)
	end
	return self
end

local sm_trans = ecs.transform "state_machine_transform"

function sm_trans.process_entity(e)
	e._animation._current = {}
	set_state(e, e.state_machine.current, 0)
end

local state_machine_sys = ecs.system "state_machine_system"

function state_machine_sys:animation_state()
	local delta = timer.delta()
	for _, eid in world:each "state_machine" do
		local e = world[eid]
		if e.state_machine.transmit_merge then
			if e.state_machine.transmit_merge(delta) then
				e.state_machine.transmit_merge = nil
			end
		end
	end
end

local iani = ecs.interface "animation"

function iani.set_state(e, name)
	local sm = e.state_machine
	if e.animation and sm and sm.nodes[name] then
		if sm.current == name then
			return
		end
		if not sm.current then
			set_state(e, name, 0)
			return
		end
		local info = sm.nodes[sm.current]
		if info and info.transmits[name] then
			set_state(e, name, info.transmits[name].duration)
			return true
		end
	end
end

function iani.play(eid, name, time)
	local e = world[eid]
	if not e or not e.animation then return false end

	local anim = e.animation[name]
	if not anim and not e.anim_clips then
		print("anim:", name, "not exist")
		return false
	end
	local real_clips
	local start_ratio = 0.0
	if not anim then
		local function find_clip_by_name(clips, name)
			for _, clip in ipairs(clips) do
				if clip.name == name then return clip end
			end
		end
		local clip = find_clip_by_name(e.anim_clips, name)
		if clip and clip.subclips then
			real_clips = #clip.subclips > 0 and {} or nil
			for _, clip_index in ipairs(clip.subclips) do
				local anim_name = e.anim_clips[clip_index].anim_name
				real_clips[#real_clips + 1] = {e.animation[anim_name], e.anim_clips[clip_index]}
			end
		else
			real_clips = clip and {{e.animation[clip.anim_name], clip }} or nil
		end
		
		if not real_clips or #real_clips < 1 then
			print("clip:", name, "not exist")
			return false
		end
		anim = real_clips[1][1]
		start_ratio = real_clips[1][2].range[1] / anim._handle:duration()
	end

	if e.state_machine then
		e.state_machine._current = nil
		play_animation(e, name, time)
	else
		e._animation._current = {
			animation = anim,
			event_state = {
				next_index = 1,
				keyframe_events = e.keyframe_events and e.keyframe_events[name] or {}
			},
			clip_state = { current = {clip_index = 1, clips = real_clips}, clips = e.anim_clips or {}},
			play_state = { ratio = start_ratio, previous_ratio = start_ratio, speed = 1.0, play = true, loop = true}
		}
	end
	return true
end

function iani.get_duration(eid)
	local e = world[eid]
	if not e or not e.animation then return 0 end
	return e._animation._current.animation._handle:duration()
end

function iani.set_time(eid, second)
	local e = world[eid]
	if not e or not e.animation then return end
	local ratio = second / e._animation._current.animation._handle:duration()
	if ratio > 1.0 then
		ratio = 1.0
	elseif ratio < 0.0 then
		ratio = 0.0
	end
	e._animation._current.play_state.ratio = ratio
end

function iani.get_time(eid)
	local e = world[eid]
	if not e or not e.animation then return 0 end
	return e._animation._current.play_state.ratio * e._animation._current.animation._handle:duration()
end

function iani.set_speed(eid, speed)
	local e = world[eid]
	if not e or not e.animation then return end
	e._animation._current.play_state.speed = speed
end

function iani.set_loop(eid, loop)
	local e = world[eid]
	if not e or not e.animation then return end
	e._animation._current.play_state.loop = loop
end

function iani.pause(eid, pause)
	local e = world[eid]
	if not e or not e.animation then return end
	e._animation._current.play_state.play = not pause
end

function iani.is_playing(eid)
	local e = world[eid]
	if not e or not e.animation then return end
	return e._animation._current.play_state.play
end

local function do_set_event(eid, anim, events)
	local e = world[eid]
	if not e or not e.animation then return end
	if not e.keyframe_events then
		e.keyframe_events = {}
	end
	e.keyframe_events[anim] = events
	if e._animation._current.animation == e.animation[anim] then
		e._animation._current.event_state.keyframe_events = e.keyframe_events[anim]
	end
end

function iani.get_collider(eid, anim, time)
	local e = world[eid]
	if not e.keyframe_events then return end

	local events = e.keyframe_events[anim]
	if not events then return end

	local colliders
	for _, event in ipairs(events.event) do
		if math.abs(time - event.time) < 0.0001 then
			colliders = {}
			for _, ev in ipairs(event.event_list) do
				if ev.event_type == "Collision" then
					colliders[#colliders + 1] = ev.collision
				end
			end
			break
		end
	end
	return colliders
end

function iani.set_events(eid, anim, events)
	if type(events) == "table" then
		do_set_event(eid, anim, events)
	elseif type(events) == "string" then
		local path = fs.path(events):localpath()
		local f = assert(lfs.open(path))
		local data = f:read "a"
		f:close()
		do_set_event(eid, anim, datalist.parse(data))
	end
end

local function do_set_clips(eid, clips)
	local e = world[eid]
	e.anim_clips = clips
end

function iani.set_clips(eid, clips)
	if type(clips) == "table" then
		do_set_clips(eid, clips)
	elseif type(clips) == "string" then
		local path = fs.path(clips):localpath()
		local f = assert(lfs.open(path))
		local data = f:read "a"
		f:close()
		do_set_clips(eid, datalist.parse(data))
	end
end

function iani.set_value(e, name, key, value)
	local sm = e.state_machine
	if not sm or not sm.nodes then
		return
	end
	local node = sm.nodes[name]
	if not node then
		return
	end
	node[key] = value
	if sm.current == name then
		set_state(e, name, 0)
	end
end
