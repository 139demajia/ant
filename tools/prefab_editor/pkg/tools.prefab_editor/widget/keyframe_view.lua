local ecs = ...
local world = ecs.world
local w = world.w
local iani      = ecs.require "ant.animation|controller.state_machine"
local iom       = ecs.require "ant.objcontroller|obj_motion"
local assetmgr 	= import_package "ant.asset"
local imgui     = require "imgui"
local uiconfig  = require "widget.config"
local uiutils   = require "widget.utils"
local joint_utils  = require "widget.joint_utils"
local utils     = require "common.utils"
local widget_utils  = require "widget.utils"
local stringify     = import_package "ant.serialize".stringify
local animation = require "hierarchy".animation
local math3d        = require "math3d"
local icons     = require "common.icons"
local mathpkg	= import_package "ant.math"
local mc, mu    = mathpkg.constant, mathpkg.util
local imodifier = ecs.require "ant.modifier|modifier"
local ika       = ecs.require "ant.animation|keyframe"
local faicons   = require "common.fa_icons"
local prefab_mgr = ecs.require "prefab_manager"
local m = {}
local current_mtl
local current_target
local current_uniform
local target_map = {}
local file_path
local joints_map
local joints_list
local current_skeleton
local joint_scale = 0.5
local sample_ratio = 50.0
local anim_eid
local current_joint
local current_anim
local allanims = {}
local anim_name_list = {}
local create_context = {}
local MODE_MTL<const> = 1
local MODE_SKE<const> = 2
local MODE_SRT<const> = 3
local anim_type_name = {
    "Linear",
    "Rebound",
    "Shake"
}
local tween_type_name = {
    "Linear",
    "CubicIn",
    "CubicOut",
    "CubicInOut",
    "BounceIn",
    "BounceOut",
    "BounceInOut",
}
local dir_name = {
    "X",
    "Y",
    "Z",
    "XY",
    "YZ",
    "XZ",
    "XYZ",
}

local TYPE_LINEAR <const>	= 1
local TYPE_REBOUND <const>	= 2
local TYPE_SHAKE <const>	= 3

local TWEEN_SAMPLE <const>	= 16

local DIR_X <const> 	= 1
local DIR_Y <const> 	= 2
local DIR_Z <const> 	= 3
local DIR_XY <const>	= 4
local DIR_YZ <const>	= 5
local DIR_XZ <const> 	= 6
local DIR_XYZ <const> 	= 7

local Dir = {
    math3d.ref(math3d.vector{1,0,0}),
    math3d.ref(math3d.vector{0,1,0}),
    math3d.ref(math3d.vector{0,0,1}),
    math3d.ref(math3d.normalize(math3d.vector{1,1,0})),
    math3d.ref(math3d.normalize(math3d.vector{0,1,1})),
    math3d.ref(math3d.normalize(math3d.vector{1,0,1})),
    math3d.ref(math3d.normalize(math3d.vector{1,1,1})),
}
-- TODO: remove this build_animation, see also pkg/ant.asset/ext_anim.lua
local function build_animation(ske, raw_animation, joint_anims, sample_ratio)
	local function tween_push_anim_key(raw_anim, joint_name, clip, time, duration, to_pos, to_rot, poseMat, reverse, sum)
		if clip.tween == mu.TWEEN_LINEAR and math.abs(to_rot[1]) < 180 and math.abs(to_rot[2]) < 180 and math.abs(to_rot[3]) < 180 then
			return
		end
		local frametime = 1.0 / sample_ratio
		duration = duration - 2 * frametime --skip the first/last frame
		if duration < frametime then
			return
		end
		local start_rot = sum and sum.rot or {0, 0, 0}
		local start_pos = sum and sum.pos or mc.ZERO
        local tween_step = 1.0 / TWEEN_SAMPLE
        for j = 1, TWEEN_SAMPLE - 1 do
			local rj = reverse and (TWEEN_SAMPLE - j) or j
            local tween_ratio = mu.tween[clip.tween](rj * tween_step)
			local target_pos = math3d.mul(Dir[clip.direction], to_pos * tween_ratio)
            local tween_local_mat = math3d.matrix{
                s = 1,
                r = math3d.quaternion{math.rad(start_rot[1] + to_rot[1] * tween_ratio),
					math.rad(start_rot[2] + to_rot[2] * tween_ratio),
					math.rad(start_rot[3] + to_rot[3] * tween_ratio)},
                t = math3d.add(start_pos, target_pos)
            }
            local tween_to_s, tween_to_r, tween_to_t = math3d.srt(math3d.mul(poseMat, tween_local_mat))
            raw_anim:push_prekey(joint_name, time + j * tween_step * duration, tween_to_s, tween_to_r, tween_to_t)
        end
    end
    local function push_anim_key(raw_anim, joint_name, clips, inherit)
		local frame_to_time = 1.0 / sample_ratio
        local poseMat = ske:joint(ske:joint_index(joint_name))
		local localMat = math3d.matrix{s = 1, r = mc.IDENTITY_QUAT, t = mc.ZERO}
        local from_s, from_r, from_t = math3d.srt(math3d.mul(poseMat, localMat))
		local sum = {pos = mc.ZERO, rot = {0, 0, 0}}
		if not clips or #clips < 1 then
			raw_anim:push_prekey(joint_name, 0, from_s, from_r, from_t)
		else
			for _, clip in ipairs(clips) do
				if clip.range[1] >= 0 and clip.range[2] >= 0 then
					local duration = clip.range[2] - clip.range[1] + 1
					local subdiv = clip.repeat_count
					if clip.type == TYPE_REBOUND then
						subdiv = 2 * subdiv
					elseif clip.type == TYPE_SHAKE then
						subdiv = 4 * subdiv
					end
					local step = (duration / subdiv) * frame_to_time
					local start_time = clip.range[1] * frame_to_time
					if duration < subdiv or step <= frame_to_time then
						raw_anim:push_prekey(joint_name, start_time, from_s, from_r, from_t)
						goto continue
					end
					local to_rot = {0,clip.amplitude_rot,0}
					if clip.rot_axis == DIR_X then
						to_rot = {clip.amplitude_rot,0,0}
					elseif clip.rot_axis == DIR_Z then
						to_rot = {0,0,clip.amplitude_rot}
					end
					
					local target_pos = math3d.mul(Dir[clip.direction], clip.amplitude_pos)
					local target_rot = {to_rot[1], to_rot[2], to_rot[3]}
					if inherit then
						target_pos = math3d.add(sum.pos, target_pos)
						target_rot[1] = sum.rot[1] + target_rot[1]
						target_rot[2] = sum.rot[2] + target_rot[2]
						target_rot[3] = sum.rot[3] + target_rot[3]
						from_s, from_r, from_t = math3d.srt(math3d.mul(poseMat, math3d.matrix{s = 1, r = math3d.quaternion{math.rad(sum.rot[1]), math.rad(sum.rot[2]), math.rad(sum.rot[3])}, t = sum.pos}))
					end
					
					localMat = math3d.matrix{s = 1, r = math3d.quaternion{math.rad(target_rot[1]), math.rad(target_rot[2]), math.rad(target_rot[3])}, t = target_pos}
					local to_s, to_r, to_t = math3d.srt(math3d.mul(poseMat, localMat))
					
					local time = start_time
					local endtime = clip.range[2] * frame_to_time
					if clip.type == TYPE_LINEAR then
						for i = 1, clip.repeat_count, 1 do
							raw_anim:push_prekey(joint_name, time, from_s, from_r, from_t)
							tween_push_anim_key(raw_anim, joint_name, clip, time, step, clip.amplitude_pos, to_rot, poseMat, false, inherit and sum)
							time = start_time + i * step - frame_to_time
							raw_anim:push_prekey(joint_name, time, to_s, to_r, to_t)
							time = time + frame_to_time
							if time >= endtime then
								break;
							end
						end
					else
						localMat = math3d.matrix{s = 1, r = math3d.quaternion{math.rad(-target_rot[1]), math.rad(-target_rot[2]), math.rad(-target_rot[3])}, t = math3d.mul(target_pos, math3d.vector(-1,-1,-1))}
						local to_s2, to_r2, to_t2 = math3d.srt(math3d.mul(poseMat, localMat))
						raw_anim:push_prekey(joint_name, time, from_s, from_r, from_t)
						for i = 1, clip.repeat_count, 1 do
							tween_push_anim_key(raw_anim, joint_name, clip, time, step, clip.amplitude_pos, to_rot, poseMat, false, inherit and sum)
							time = time + step
							raw_anim:push_prekey(joint_name, time, to_s, to_r, to_t)
							tween_push_anim_key(raw_anim, joint_name, clip, time, step, clip.amplitude_pos, to_rot, poseMat, true, inherit and sum)
							if clip.type == TYPE_REBOUND then
								time = (i == clip.repeat_count) and (clip.range[2] * frame_to_time) or (time + step)
								raw_anim:push_prekey(joint_name, time, from_s, from_r, from_t)
							elseif clip.type == TYPE_SHAKE then
								time = time + step
								tween_push_anim_key(raw_anim, joint_name, clip, time, step, -clip.amplitude_pos, {-to_rot[1], -to_rot[2], -to_rot[3]}, poseMat, false, inherit and sum)
								time = time + step
								raw_anim:push_prekey(joint_name, time, to_s2, to_r2, to_t2)
								tween_push_anim_key(raw_anim, joint_name, clip, time, step, -clip.amplitude_pos, {-to_rot[1], -to_rot[2], -to_rot[3]}, poseMat, true, inherit and sum)
								time = time + step
							end
							if time >= endtime then
								break;
							end
						end
						if clip.type == TYPE_SHAKE then
							raw_anim:push_prekey(joint_name, clip.range[2] * frame_to_time, from_s, from_r, from_t)
						end
					end
					if inherit then
						sum = {pos = target_pos, rot = target_rot}
					end
				end
				::continue::
			end
		end
    end
	
	local flags = {}
    for _, anim in ipairs(joint_anims) do
		flags[ske:joint_index(anim.target_name)] = true
        raw_animation:clear_prekey(anim.target_name)
        push_anim_key(raw_animation, anim.target_name, anim.clips, anim.inherit and anim.inherit[3])
    end
	local ske_count = #ske
	for i=1, ske_count do
		if not flags[i] then
			local joint_name = ske:joint_name(i)
			raw_animation:clear_prekey(joint_name)
        	push_anim_key(raw_animation, joint_name)
		end
    end
    return raw_animation:build()
end

local function update_animation()
    local animtype = current_anim.type
    local runtime_anim = current_anim.runtime_anim
    if animtype == "ske" then
        runtime_anim._handle = build_animation(current_skeleton._handle, runtime_anim.raw_animation, current_anim.target_anims, sample_ratio)
    else
        local get_keyframe_value = function (type, clip)
            if type == "mtl" then
                return clip.value
            elseif type == "srt" then
                local value = {1, 0, 0, 0, 0, 0, 0}
                value[clip.rot_axis + 1] = clip.amplitude_rot
                if clip.direction < 4 then
                    value[clip.direction + 4] = clip.amplitude_pos
                elseif clip.direction == 4 then--XY
                    value[5] = clip.amplitude_pos
                    value[6] = clip.amplitude_pos
                elseif clip.direction == 5 then--YZ
                    value[6] = clip.amplitude_pos
                    value[7] = clip.amplitude_pos
                elseif clip.direction == 6 then--XZ
                    value[5] = clip.amplitude_pos
                    value[7] = clip.amplitude_pos
                elseif clip.direction == 7 then--XYZ
                    value[5] = clip.amplitude_pos
                    value[6] = clip.amplitude_pos
                    value[7] = clip.amplitude_pos
                end
                return value
            end
        end
        for _, anim in ipairs(current_anim.target_anims) do
            if #anim.clips < 1 then
                goto continue
            end
            local keyframes = {}
            local init_value
            if animtype == "srt" then
                init_value = {1, 0, 0, 0, 0, 0, 0}
            elseif animtype == "mtl" then
                init_value = anim.init_value
            end
            local from = init_value
            local last_clip = anim.clips[1]
            for _, clip in ipairs(anim.clips) do
                if clip.range[1] == last_clip.range[2] + 1 then
                    from = get_keyframe_value(animtype, last_clip)
                else
                    if clip.range[1] > 0 then
                        keyframes[#keyframes + 1] = {time = ((clip == last_clip) and 0 or (last_clip.range[2] + 1) / sample_ratio), value = init_value}
                    end
                    from = init_value
                end
                local fromvalue = {}
                for _, value in ipairs(from) do
                    fromvalue[#fromvalue + 1] = value
                end
                keyframes[#keyframes + 1] = {time = clip.range[1] / sample_ratio, tween = clip.tween, value = fromvalue}
                local tovalue = get_keyframe_value(animtype, clip)
                if animtype == "mtl" then
                    local tv = {}
                    for _, value in ipairs(tovalue) do
                        tv[#tv + 1] = value * clip.scale
                    end
                    tovalue = tv
                end
                keyframes[#keyframes + 1] = {time = clip.range[2] / sample_ratio, tween = clip.tween, value = tovalue}
                last_clip = clip
            end
            local endclip = anim.clips[#anim.clips]
            if endclip and endclip.range[2] < current_anim.frame_count - 1 then
                keyframes[#keyframes + 1] = {time = (endclip.range[2] + 1) / sample_ratio, value = init_value}
                if current_anim.frame_count > endclip.range[2] + 1 then
                    keyframes[#keyframes + 1] = {time = current_anim.frame_count / sample_ratio, value = init_value}
                end
            end
            imodifier.delete(anim.modifier)
            anim.modifier = nil
            if #keyframes > 0 then
                if animtype == "mtl" then
                    anim.modifier = imodifier.create_mtl_modifier(current_target, anim.target_name, keyframes, false, true)
                elseif animtype == "srt" then
                    anim.modifier = imodifier.create_srt_modifier(target_map[anim.target_name], 0, keyframes, false, true)
                end
            end
            ::continue::
        end
    end
end

local function min_max_range_value(clips, clip_index)
    local min = 0
    local max = math.ceil(current_anim.duration * sample_ratio) - 1
    if clip_index < #clips then
        max = clips[clip_index + 1].range[1] - 1
    end
    if clip_index > 1 and clip_index <= #clips then
        min = clips[clip_index - 1].range[2] + 1
    end
    return min, max
end

local function on_move_clip(move_type, current_clip_index, move_delta)
    local anim = current_anim.target_anims[current_anim.selected_layer_index]
    local clips = anim.clips
    if current_clip_index <= 0 or current_clip_index > #clips then return end
    local clip = clips[current_clip_index]
    if not clip then return end
    local min_value, max_value = min_max_range_value(clips, current_clip_index)
    if move_type == 1 then
        local new_value = clip.range[1] + move_delta
        if new_value < 0 then
            new_value = 0
        end
        if new_value >= clip.range[2] then
            new_value = clip.range[2] - 1
        end
        clip.range[1] = new_value
        clip.range_ui[1] = clip.range[1]
    elseif move_type == 2 then
        local new_value = clip.range[2] + move_delta
        if new_value <= clip.range[1] then
            new_value = clip.range[1] + 1
        end
        if new_value > max_value then
            new_value = max_value
        end
        clip.range[2] = new_value
        clip.range_ui[2] = clip.range[2]
    elseif move_type == 3 then
        local new_value1 = clip.range[1] + move_delta
        local new_value2 = clip.range[2] + move_delta
        if new_value1 >= min_value and new_value2 <= max_value then
            clip.range[1] = new_value1
            clip.range[2] = new_value2
            clip.range_ui[1] = clip.range[1]
            clip.range_ui[2] = clip.range[2]
        end
    end
    current_anim.dirty_layer = current_anim.selected_layer_index
    update_animation()
end
local function clip_exist(clips, name)
    for _, v in ipairs(clips) do
        if v.name == name then
            return true
        end
    end
end

local function find_anim_by_name(name)
    if not current_anim then return end
    for index, value in ipairs(current_anim.target_anims) do
        if name == value.target_name then
            return index
        end
    end
end

local function find_greater_clip(current, clips, pos)
    local find
    for index, value in ipairs(clips) do
        if index ~= current then
            if pos >= value.range[1] and pos <= value.range[2] then
                find = index
                break
            end
        end
    end
    if not find then
        for index, value in ipairs(clips) do
            if index ~= current then
                if pos < value.range[1] then
                    return index
                end
            end
        end
        return 0
    else
        return -1
    end
end

local function is_index_valid(index)
    if current_anim.selected_layer_index > 0 then
        local clips = current_anim.target_anims[current_anim.selected_layer_index].clips
        for _, clip in ipairs(clips) do
            if (index >= clip.range[1] and index <= clip.range[2]) then
                return false
            end
        end
    end
    return index >= 0 and index <= math.ceil(current_anim.duration * sample_ratio) - 1
end

local new_clip_pop = false
local start_frame_ui = {0, speed = 1, min = 0}
local new_range_start = 0
local new_range_end = 1
local max_repeat<const> = 10

local function get_current_target_name()
    if current_anim.type == "mtl" then
        return current_uniform
    elseif current_anim.type == "srt" then
        return #current_anim.target_anims > 0 and current_anim.target_anims[1].target_name or nil
    else
        return current_joint and current_joint.name or nil
    end
end
local function get_or_create_target_anim(tn, init_value)
    if not current_anim or not tn then
        return
    end
    for _, value in ipairs(current_anim.target_anims) do
        if tn == value.target_name then
            return value;
        end
    end
    current_anim.target_anims[#current_anim.target_anims + 1] = {
        target_name = tn,
        init_value = init_value,
        clips = {},
        inherit = {false, false, false}, -- s, r, t
        inherit_ui = {{false}, {false}, {false}}
    }
    return current_anim.target_anims[#current_anim.target_anims]
end

local function create_clip()
    if not new_clip_pop or (not current_joint and not current_uniform and not current_target) then
        return
    end
    local title = "New Clip"
    if not imgui.windows.IsPopupOpen(title) then
        imgui.windows.OpenPopup(title)
    end

    local change, opened = imgui.windows.BeginPopupModal(title, imgui.flags.Window{"AlwaysAutoResize", "NoClosed"})
    if change then
        imgui.widget.Text("StartFrame:")
        imgui.cursor.SameLine()
        if imgui.widget.DragInt("##StartFrame", start_frame_ui) then
            if start_frame_ui[1] < 0 then
                start_frame_ui[1] = 0
            end
            new_range_start = start_frame_ui[1]
            new_range_end = new_range_start + 1
        end
        if is_index_valid(new_range_start) and is_index_valid(new_range_end) then
            if imgui.widget.Button "Create" then
                local target_name = get_current_target_name()
                local anim = get_or_create_target_anim(target_name)
                local clips = anim.clips
                local new_clip
                if current_anim.type == "mtl" then
                    new_clip = {
                        value = {0.0, 0.0, 0.0, 0.0},
                        value_ui = {0.0, 0.0, 0.0, 0.0, speed = 1},
                        scale = 1.0,
                        scale_ui = {1.0, min = 0, max = 10, speed = 0.1}
                    }
                else
                    new_clip = {
                        type = 1,
                        repeat_count = 1,
                        random_amplitude = false,
                        direction = 2,
                        rot_axis = 2,
                        amplitude_pos = 0,
                        amplitude_rot = 0,
                        repeat_ui = {1, speed = 1, min = 1, max = max_repeat},
                        random_amplitude_ui = { false },
                        amplitude_pos_ui = {0, speed = 0.1},
                        amplitude_rot_ui = {0, speed = 1},
                    }
                end
                new_clip.range = {new_range_start, new_range_end}
                new_clip.range_ui = {new_range_start, new_range_end, speed = 1}
                new_clip.tween = 1
                clips[#clips + 1] = new_clip
                table.sort(clips, function(a, b) return a.range[2] < b.range[1] end)
                for index, value in ipairs(clips) do
                    if new_clip == value then
                        current_anim.selected_clip_index = index
                        break
                    end
                end
                local index, _ = find_anim_by_name(target_name)
                current_anim.selected_layer_index = index
                current_anim.dirty_layer = -1
                new_clip_pop = false
            end
        else
            imgui.widget.Text("Invalid start range!")
        end
        imgui.cursor.SameLine()
        if imgui.widget.Button(faicons.ICON_FA_SQUARE_XMARK.." Cancel") then
            new_clip_pop = false
        end
        imgui.windows.EndPopup()
    end
end
local function max_range_value()
    if not current_anim then return 1 end
    local max_value = 1
    for _, joint_anim in ipairs(current_anim.target_anims) do
        local clips = joint_anim.clips
        if #clips > 0 then
            if max_value < clips[#clips].range[2] then
                max_value = clips[#clips].range[2]
            end
        end
    end
    return max_value
end

local function show_current_detail()
    if not current_anim then return end
    local anim_type = current_anim.type
    imgui.widget.PropertyLabel("FrameCount:")
    if imgui.widget.DragInt("##FrameCount", current_anim.frame_count_ui) then
        if current_anim.frame_count_ui[1] < max_range_value() + 1 then
            current_anim.frame_count_ui[1] = max_range_value() + 1
        end
        current_anim.frame_count = current_anim.frame_count_ui[1]
        local d = current_anim.frame_count / sample_ratio
        current_anim.duration = d
        if anim_type == "ske" then
            current_anim.runtime_anim._duration = d
            current_anim.runtime_anim.raw_animation:setup(current_skeleton._handle, d)
            current_anim.runtime_anim._handle = current_anim.runtime_anim.raw_animation:build() 
        end
        current_anim.dirty = true
    end
    local target_name = get_current_target_name()
    if (anim_type == "mtl" and not current_uniform) or (anim_type == "ske" and not current_joint) or not target_name then
        return
    end
    imgui.widget.Text(target_name .. ":")
    imgui.cursor.SameLine()
    if imgui.widget.Button("NewClip") then
        new_clip_pop = true
    end
    create_clip()
    if current_anim.selected_layer_index < 1 then
        return
    end
    local anim_layer = current_anim.target_anims[current_anim.selected_layer_index]
    local clips = anim_layer.clips
    
    -- imgui.cursor.SameLine()
    -- if imgui.widget.Checkbox("inherit", anim_layer.inherit_ui[1]) then
    --     anim_layer.inherit[1] = anim_layer.inherit_ui[1][1]
    --     update_animation()
    -- end
    -- imgui.cursor.SameLine()
    -- if imgui.widget.Checkbox("inherit", anim_layer.inherit_ui[2]) then
    --     anim_layer.inherit[2] = anim_layer.inherit_ui[2][1]
    --     update_animation()
    -- end
    imgui.cursor.SameLine()
    if imgui.widget.Checkbox("inherit", anim_layer.inherit_ui[3]) then
        anim_layer.inherit[3] = anim_layer.inherit_ui[3][1]
        update_animation()
    end

    if current_anim.selected_clip_index < 1 then
        return
    else
        imgui.cursor.SameLine()
        if imgui.widget.Button(faicons.ICON_FA_TRASH.." DelClip") then
            table.remove(clips, current_anim.selected_clip_index)
            current_anim.selected_clip_index = 0
            current_anim.dirty_layer = -1
            update_animation()
            return
        end
    end

    local current_clip = clips[current_anim.selected_clip_index]
    local name = get_current_target_name()
    if not current_clip or anim_layer.target_name ~= name then
        return
    end

    imgui.cursor.Separator()
    imgui.widget.PropertyLabel("FrameRange")
    local old_range = {current_clip.range_ui[1], current_clip.range_ui[2]}
    local dirty = false
    if imgui.widget.DragInt("##Range", current_clip.range_ui) then
        local range_ui = current_clip.range_ui
        local head = false
        if old_range[1] ~= range_ui[1] then
            head = true
            local find = find_greater_clip(current_anim.selected_clip_index, clips, range_ui[1])
            if find < 0 then
                range_ui[1] = old_range[1]
            else
                if find > 0 then
                    local max = clips[find].range[1] - 1
                    if range_ui[2] < 0 or range_ui[2] > max then
                        range_ui[2] = max
                    end
                else
                    if range_ui[2] < 0 then
                        range_ui[2] = current_anim.frame_count - 1
                    end
                end
            end
        elseif old_range[2] ~= range_ui[2] then
            local find = find_greater_clip(current_anim.selected_clip_index, clips, range_ui[2])
            if find < 0 then
                range_ui[2] = old_range[2]
            else
                local left_index = find - 1
                if find > 1 and left_index ~= current_anim.selected_clip_index then
                    local min = clips[left_index].range[2] + 1
                    if range_ui[1] < min then
                        range_ui[1] = min
                    end
                else
                    if range_ui[1] < 0 then
                        range_ui[1] = 0
                    end
                end
            end
        end
        if head then
            if range_ui[1] >= range_ui[2] then
                range_ui[1] = range_ui[2] - 1
            elseif range_ui[1] < 0 then
                range_ui[1] = 0
            end
        else
            if range_ui[2] <= range_ui[1] then
                range_ui[2] = range_ui[1] + 1
            elseif range_ui[2] >= current_anim.frame_count then
                range_ui[2] = current_anim.frame_count - 1
            end
        end
        current_clip.range = {range_ui[1], range_ui[2]}
        current_anim.dirty_layer = current_anim.selected_layer_index
        dirty = true
    end
    imgui.widget.PropertyLabel("TweenType")
    if imgui.widget.BeginCombo("##TweenType", {tween_type_name[current_clip.tween], flags = imgui.flags.Combo {}}) then
        for i, type in ipairs(tween_type_name) do
            if imgui.widget.Selectable(type, current_clip.tween == i) then
                current_clip.tween = i
                dirty = true
            end
        end
        imgui.widget.EndCombo()
    end
    if anim_type == "mtl" then
        imgui.widget.PropertyLabel("UniformValue")
        local ui_data = current_clip.value_ui
        if imgui.widget.ColorEdit("##UniformValue", ui_data) then
            current_clip.value = {ui_data[1], ui_data[2], ui_data[3], ui_data[4]}
            dirty = true
        end
        imgui.widget.PropertyLabel("Scale")
        ui_data = current_clip.scale_ui
        if imgui.widget.DragFloat("##Scale", ui_data) then
            current_clip.scale = ui_data[1]
            dirty = true
        end
    else
        if anim_type == "ske" then
            imgui.widget.PropertyLabel("AnimationType")
            if imgui.widget.BeginCombo("##AnimationType", {anim_type_name[current_clip.type], flags = imgui.flags.Combo {}}) then
                for i, type in ipairs(anim_type_name) do
                    if imgui.widget.Selectable(type, current_clip.type == i) then
                        current_clip.type = i
                        dirty = true
                    end
                end
                imgui.widget.EndCombo()
            end
            imgui.widget.PropertyLabel("Repeat")
            if imgui.widget.DragInt("##Repeat", current_clip.repeat_ui) then
                local count = current_clip.repeat_ui[1]
                if count > max_repeat then
                    count = max_repeat
                elseif count < 1 then
                    count = 1
                end
                current_clip.repeat_count = count
                current_clip.repeat_ui[1] = count
                dirty = true
            end
        end
        imgui.widget.PropertyLabel("Direction")
        if imgui.widget.BeginCombo("##Direction", {dir_name[current_clip.direction], flags = imgui.flags.Combo {}}) then
            for i, type in ipairs(dir_name) do
                if imgui.widget.Selectable(type, current_clip.direction == i) then
                    current_clip.direction = i
                    dirty = true
                end
            end
            imgui.widget.EndCombo()
        end

        imgui.widget.PropertyLabel("AmplitudePos")
        local ui_data = current_clip.amplitude_pos_ui
        if imgui.widget.DragFloat("##AmplitudePos", ui_data) then
            current_clip.amplitude_pos = ui_data[1]
            dirty = true
        end

        imgui.widget.PropertyLabel("RotAxis")
        if imgui.widget.BeginCombo("##RotAxis", {dir_name[current_clip.rot_axis], flags = imgui.flags.Combo {}}) then
            for i = 1, 3 do
                if imgui.widget.Selectable(dir_name[i], current_clip.rot_axis == i) then
                    current_clip.rot_axis = i
                    dirty = true
                end
            end
            imgui.widget.EndCombo()
        end
        imgui.widget.PropertyLabel("AmplitudeRot")
        ui_data = current_clip.amplitude_rot_ui
        if imgui.widget.DragFloat("##AmplitudeRot", ui_data) then
            current_clip.amplitude_rot = ui_data[1]
            dirty = true
        end
    end
    if dirty then
        update_animation()
    end
end

local function anim_pause(p)
    for _, current in pairs(allanims) do
        if current.type == "ske" then
            iani.pause(anim_eid, p)
        else
            for _, anim in ipairs(current.target_anims) do
                if anim.modifier then
                    local kfa <close> = world:entity(anim.modifier.anim_eid)
                    ika.stop(kfa)
                end
            end
        end
    end
end

local function anim_set_loop(loop)
    for _, current in pairs(allanims) do
        if current.type == "ske" then
            iani.set_loop(anim_eid, loop)
        else
            for _, anim in ipairs(current.target_anims) do
                if anim.modifier then
                    local kfa <close> = world:entity(anim.modifier.anim_eid)
                    ika.set_loop(kfa, loop)
                end
            end
        end
    end
end

local function anim_set_speed(speed)
    if current_anim.type == "ske" then
        iani.set_speed(anim_eid, speed)
    end
end

local function anim_set_time(t)
    if current_anim.type == "ske" then
        iani.set_time(anim_eid, t)
    else
        for _, anim in ipairs(current_anim.target_anims) do
            if anim.modifier then
                local kfa <close> = world:entity(anim.modifier.anim_eid)
                ika.set_time(kfa, t)
            end
        end
    end
end

local anim_name = ""
local anim_duration = 30
local anim_name_ui = {text = ""}
local duration_ui = {30, speed = 1, min = 1}
local new_anim_widget = false

local function create_animation(animtype, name, duration, target_anims)
    if allanims[name] then
        local msg = name .. " has existed!"
        widget_utils.message_box({title = "Create Animation Error", info = msg})
    else
        local td = duration / sample_ratio
        local new_anim
        if animtype == "mtl" or animtype == "srt" then
            new_anim = {}
        else
            new_anim = {
                raw_animation = animation.new_raw_animation(),
                _duration = td,
                _sampling_context = animation.new_sampling_context(1)
            }
            new_anim.raw_animation:setup(current_skeleton._handle, td)
            local e <close> = world:entity(anim_eid, "animation:in")
            e.animation[name] = new_anim
        end
        local edit_anim = {
            type = animtype,
            name = name,
            dirty = true,
            dirty_layer = -1,-- [1...n]: dirty index, 0: no dirty, -1: all dirty
            duration = td,
            frame_count = duration,
            frame_count_ui = {duration, speed = 1},
            is_playing = false,
            selected_layer_index = -1,
            selected_frame = -1,
            current_frame = 0,
            clip_range_dirty = 0,
            selected_clip_index = 0,
            target_anims = target_anims or {},
            runtime_anim = new_anim
        }
        allanims[name] = edit_anim
        current_anim = edit_anim
        anim_name_list[#anim_name_list + 1] = name
        table.sort(anim_name_list)
        if create_context then
            if animtype == "mtl" then
                for _, desc in ipairs(create_context.desc) do
                    get_or_create_target_anim(desc.name, desc.init_value)
                end
            elseif animtype == "srt" then
                get_or_create_target_anim(create_context.desc[1].name)
            end
            create_context = nil
        end
    end
end

function m.new()
    if not new_anim_widget then return end
    local title = "New Animation"
    if not imgui.windows.IsPopupOpen(title) then
        imgui.windows.OpenPopup(title)
    end

    local change, opened = imgui.windows.BeginPopupModal(title, imgui.flags.Window{"AlwaysAutoResize", "NoClosed"})
    if change then
        imgui.widget.Text("Name:")
        imgui.cursor.SameLine()
        if imgui.widget.InputText("##Name", anim_name_ui) then
            anim_name = tostring(anim_name_ui.text)
        end
        imgui.widget.Text("Duration:")
        imgui.cursor.SameLine()
        if imgui.widget.DragInt("##Duration", duration_ui) then
            if duration_ui[1] < 1 then
                duration_ui[1] = 1
            end
            anim_duration = duration_ui[1]
        end
        if imgui.widget.Button(faicons.ICON_FA_SQUARE_CHECK.." OK") then
            new_anim_widget = false
            if anim_name ~= "" then
                create_animation(create_context and create_context.type or "ske", anim_name, anim_duration)
            end
        end
        imgui.cursor.SameLine()
        if imgui.widget.Button(faicons.ICON_FA_SQUARE_XMARK.." Cancel") then
            new_anim_widget = false
        end
        imgui.windows.EndPopup()
    end
end
local ui_playall = { false }
local ui_loop = {true}
local ui_speed = {1, min = 0.1, max = 10, speed = 0.1}
function m.clear(keep_skel)
    if current_skeleton and current_joint then
        joint_utils:set_current_joint(current_skeleton, nil)
    end
    allanims = {}
    anim_name_list = {}
    target_map = {}
    if current_anim then
        for _, anim in ipairs(current_anim.target_anims) do
            if anim.type == "srt" or anim.type == "mtl" then
                imodifier.delete(anim.modifier)
            end
        end
    end
    create_context = nil
    current_anim = nil
    current_joint = nil
    current_uniform = nil
    current_mtl = nil
    current_target = nil
    if not keep_skel then
        anim_eid = nil
        current_skeleton = nil
        if joints_list then
            for _, joint in ipairs(joints_list) do
                if joint.mesh then
                    w:remove(joint.mesh)
                end
                joint.mesh = nil
            end
        end
        joint_utils.on_select_joint = nil
        joint_utils.update_joint_pose = nil
    end
end

local function on_select_target(tn)
    if not current_anim then
        return
    end
    local layer_index = find_anim_by_name(tn)
    if layer_index then
        current_anim.selected_layer_index = layer_index
        if current_anim.selected_clip_index < 1 and #current_anim.target_anims[layer_index].clips > 0 then
            current_anim.selected_clip_index = 1
        end
    else
        current_anim.selected_layer_index = -1
        current_anim.selected_clip_index = 0
    end
    current_anim.dirty = true
end

local function show_uniforms()
    for _, anim in ipairs(current_anim.target_anims) do
        if imgui.widget.Selectable(anim.target_name, current_uniform and current_uniform == anim.target_name) then
            current_uniform = anim.target_name
            on_select_target(current_uniform)
        end
    end
end

local function show_joints()
    if joints_map and current_skeleton then
        joint_utils:show_joints(joints_map.root)
        if current_joint ~= joint_utils.current_joint then
            current_joint = joint_utils.current_joint
            on_select_target(current_joint.name)
        end
    end
end

local function play_animation(current)
    if current.type == "ske" then
        iani.play(anim_eid, {name = current.name, loop = ui_loop[1], speed = ui_speed[1], manual = false})
    else
        for _, anim in ipairs(current.target_anims) do
            if anim.modifier then
                if anim.type == "srt"  then
                    target_map[anim.target_name] = prefab_mgr:get_eid_by_name(anim.target_name)
                    imodifier.set_target(anim.modifier, target_map[anim.target_name])
                elseif anim.type == "mtl" then
                    imodifier.set_target(anim.modifier, current_target)
                end
                imodifier.start(anim.modifier, {loop = ui_loop[1]})
            end
        end
    end
end
function m.show()
    local viewport = imgui.GetMainViewport()
    imgui.windows.SetNextWindowPos(viewport.WorkPos[1], viewport.WorkPos[2] + viewport.WorkSize[2] - uiconfig.BottomWidgetHeight, 'F')
    imgui.windows.SetNextWindowSize(viewport.WorkSize[1], uiconfig.BottomWidgetHeight, 'F')
    if imgui.windows.Begin("Skeleton", imgui.flags.Window { "NoCollapse", "NoScrollbar", "NoClosed" }) then
        if current_skeleton then
            if imgui.widget.Button(faicons.ICON_FA_FILE_PEN.." New") then
                new_anim_widget = true
            end
            imgui.cursor.SameLine()
        end
        m.new()
        if imgui.widget.Button(faicons.ICON_FA_FOLDER_OPEN.." Load") then
            local anim_filename = uiutils.get_open_file_path("Load Animation", "anim")
            if anim_filename then
                m.load(anim_filename)
            end
        end

        imgui.cursor.SameLine()
        if imgui.widget.Button(faicons.ICON_FA_FLOPPY_DISK.." Save") then
            m.save(file_path)
        end
        imgui.cursor.SameLine()
        imgui.widget.Text("Mode: "..(current_anim and current_anim.type or ""))
        if #anim_name_list > 0 then
            imgui.cursor.SameLine()
            imgui.cursor.PushItemWidth(150)
            if imgui.widget.BeginCombo("##AnimList", {current_anim.name, flags = imgui.flags.Combo {}}) then
                for _, name in ipairs(anim_name_list) do
                    if imgui.widget.Selectable(name, current_anim.name == name) then
                        current_anim.selected_layer_index = 0
                        current_anim.selected_clip_index = 0
                        current_anim = allanims[name]
                        current_anim.dirty = true
                        current_anim.selected_layer_index = 0
                        current_anim.selected_clip_index = 0
                        current_anim.dirty_layer = -1
                    end
                end
                imgui.widget.EndCombo()
            end
            imgui.cursor.PopItemWidth()
        end
        if current_anim then
            imgui.cursor.SameLine()
            if imgui.widget.Checkbox("all ", ui_playall) then
                anim_set_loop(ui_playall[1])
            end
            imgui.cursor.SameLine()
            if current_anim.type == "mtl" or current_anim.type == "srt" then
                for _, anim in ipairs(current_anim.target_anims) do
                    if anim.modifier then
                        local kfa <close> = world:entity(anim.modifier.anim_eid)
                        current_anim.is_playing = ika.is_playing(kfa)
                        if current_anim.is_playing then
                            current_anim.current_frame = math.floor(ika.get_time(kfa) * sample_ratio)
                        end
                        break
                    end
                end
            else
                if anim_eid then
                    current_anim.is_playing = iani.is_playing(anim_eid)
                    if current_anim.is_playing then
                        current_anim.current_frame = math.floor(iani.get_time(anim_eid) * sample_ratio)
                    end
                end
            end
            
            local icon = current_anim.is_playing and icons.ICON_PAUSE or icons.ICON_PLAY
            local imagesize = icon.texinfo.width * icons.scale
            if imgui.widget.ImageButton("##play ", assetmgr.textures[icon.id], imagesize, imagesize) then
                if current_anim.is_playing then
                    anim_pause(true)
                else
                    if ui_playall[1] then
                        for _, current in pairs(allanims) do
                            play_animation(current)
                        end
                    else
                        play_animation(current_anim)
                    end
                end
            end
            imgui.cursor.SameLine()
            if imgui.widget.Checkbox("loop ", ui_loop) then
                anim_set_loop(ui_loop[1])
            end
            imgui.cursor.SameLine()
            imgui.cursor.PushItemWidth(50)
            if imgui.widget.DragFloat("speed ", ui_speed) then
                anim_set_speed(ui_speed[1])
            end
            imgui.cursor.PopItemWidth()
            imgui.cursor.SameLine()
            local current_time = 0
            if current_anim.type == "ske" then
                current_time = anim_eid and iani.get_time(anim_eid) or 0
            else
                for _, anim in ipairs(current_anim.target_anims) do
                    if anim.modifier then
                        local kfa <close> = world:entity(anim.modifier.anim_eid)
                        current_time = ika.get_time(kfa)
                        break
                    end
                end
            end
            imgui.widget.Text(string.format("Selected Frame: %d Time: %.2f(s) Current Frame: %d/%d Time: %.2f/%.2f(s)", current_anim.selected_frame, current_anim.selected_frame / sample_ratio, math.floor(current_time * sample_ratio), math.floor(current_anim.duration * sample_ratio), current_time, current_anim.duration))
        
            if current_anim.type == "mtl" and current_mtl then
                imgui.cursor.SameLine()
                imgui.widget.Text("material path: " .. tostring(current_mtl))
            end
        end
        if imgui.table.Begin("SkeletonColumns", 3, imgui.flags.Table {'Resizable', 'ScrollY'}) then
            imgui.table.SetupColumn("Targets", imgui.flags.TableColumn {'WidthStretch'}, 1.0)
            imgui.table.SetupColumn("Detail", imgui.flags.TableColumn {'WidthStretch'}, 1.5)
            imgui.table.SetupColumn("AnimationLayer", imgui.flags.TableColumn {'WidthStretch'}, 6.5)
            imgui.table.HeadersRow()

            imgui.table.NextColumn()
            local child_width, child_height = imgui.windows.GetContentRegionAvail()
            imgui.windows.BeginChild("##show_target", child_width, child_height, false)
            if current_anim then
                if current_anim.type == "mtl" then
                    show_uniforms()
                elseif current_anim.type == "ske" then
                    show_joints()
                end
            end
            imgui.windows.EndChild()

            imgui.table.NextColumn()
            child_width, child_height = imgui.windows.GetContentRegionAvail()
            imgui.windows.BeginChild("##show_detail", child_width, child_height, false)
            show_current_detail()
            imgui.windows.EndChild()

            imgui.table.NextColumn()
            child_width, child_height = imgui.windows.GetContentRegionAvail()
            imgui.windows.BeginChild("##show_layers", child_width, child_height, false)

            if current_anim then
                local imgui_message = {}
                imgui.widget.SimpleSequencer(current_anim, imgui_message)
                current_anim.dirty = false
                current_anim.clip_range_dirty = 0
                current_anim.dirty_layer = 0
                local move_type
                local move_delta
                for k, v in pairs(imgui_message) do
                    if k == "pause" then
                        anim_pause(true)
                        current_anim.current_frame = v
                        anim_set_time(v / sample_ratio)
                    elseif k == "selected_frame" then
                        current_anim.selected_frame = v
                    elseif k == "selected_clip_index" then
                        current_anim.selected_clip_index = v
                    elseif k == "selected_layer_index" then
                        current_anim.selected_layer_index = v
                        if v > 0 and v <= #current_anim.target_anims then
                            local name = current_anim.target_anims[v].target_name
                            if current_anim.type == "mtl" then
                                current_uniform = name
                            elseif current_anim.type == "ske" then
                                joint_utils:set_current_joint(current_skeleton, name)
                            end
                        end
                    elseif k == "move_type" then
                        move_type = v
                    elseif k == "move_delta" then
                        move_delta = v
                    end
                end

                if move_type and move_type ~= 0 then
                    on_move_clip(move_type, current_anim.selected_clip_index, move_delta)
                end
            end
            imgui.windows.EndChild()

            imgui.table.End()
        end
    end
    imgui.windows.End()
end

function m.save(path)
    if not next(allanims) then
        return
    end
    local filename
    if not path then
        filename = widget_utils.get_saveas_path("Save Animation", "anim")
        if not filename then return end
    else
        filename = path
    end
    local animdata = {}
    for _, anim in pairs(allanims) do
        local target_anims = utils.deep_copy(anim.target_anims)
        for _, subanim in ipairs(target_anims) do
            for _, clip in ipairs(subanim.clips) do
                clip.range_ui = nil
                clip.repeat_ui = nil
                clip.random_amplitude_ui = nil
                clip.amplitude_pos_ui = nil
                clip.amplitude_rot_ui = nil
                clip.scale_ui = nil
                clip.value_ui = nil
            end
            subanim.inherit_ui = nil
            subanim.modifier = nil
        end
        animdata[#animdata + 1] = {
            type = anim.type,
            name = anim.name,
            duration = anim.duration,
            target_anims = target_anims,
            sample_ratio = sample_ratio,
            skeleton = (anim.type == "ske") and current_skeleton.filename or nil
        }
    end
    utils.write_file(filename, stringify(animdata))
    if file_path ~= filename then
        file_path = filename
    end
end

local lfs = require "bee.filesystem"
local datalist  = require "datalist"
local serialize = import_package "ant.serialize"
function m.load(path)
    m.clear(true)
    local path = lfs.path(path)
    local f = assert(io.open(path:string()))
    local data = f:read "a"
    f:close()
    local animlist = datalist.parse(data)
    for _, anim in ipairs(animlist) do
        local is_valid = true
        for _, subanim in ipairs(anim.target_anims) do
            if anim.type == "mtl" then
                for _, clip in ipairs(subanim.clips) do
                    clip.range_ui = {clip.range[1], clip.range[2], speed = 1}
                    clip.value_ui = {clip.value[1], clip.value[2], clip.value[3], clip.value[4], speed = 1}
                    clip.scale_ui = {clip.scale, min = 0, max = 10, speed = 0.1}
                end
                if not current_uniform then
                    current_uniform = subanim.target_name
                end
            else
                for _, clip in ipairs(subanim.clips) do
                    clip.range_ui = {clip.range[1], clip.range[2], speed = 1}
                    if anim.type == "ske" then
                        clip.repeat_ui = {clip.repeat_count, speed = 1, min = 1, max = max_repeat}
                        clip.random_amplitude_ui = {clip.random_amplitude}
                    end
                    clip.amplitude_pos_ui = {clip.amplitude_pos, speed = 0.1}
                    clip.amplitude_rot_ui = {clip.amplitude_rot, speed = 1}
                end
                if anim.type == "ske" then
                    local joint = joint_utils:get_joint_by_name(current_skeleton, subanim.target_name)
                    if not joint then
                        is_valid = false
                        assert(false)
                    end
                end
            end
            if not subanim.inherit then
                subanim.inherit = {false, false, false}
            end
            subanim.inherit_ui = {{subanim.inherit[1]}, {subanim.inherit[2]}, {subanim.inherit[3]}}

            target_map[subanim.target_name] = prefab_mgr:get_eid_by_name(subanim.target_name)
        end
        if not is_valid then
            return
        end
        create_animation(anim.type, anim.name, math.floor(anim.duration * sample_ratio), anim.target_anims)
        sample_ratio = anim.sample_ratio
        update_animation()
    end
    file_path = path:string()
end
local function read_file(fn)
    local f <close> = assert(io.open(fn:string()))
    return f:read "a"
end
function m.create_target_animation(at, target)
    local e <close> = world:entity(target, "material?in name:in")
    create_context = {}
    create_context.type = at
    new_anim_widget = true
    if at == "srt" then
        create_context.desc = {{name = e.name}}
        target_map[e.name] = target
    elseif at == "mtl" then
        local mtlpath = e.material
        if mtlpath then
            if string.find(e.material, ".glb|") then
                mtlpath = mtlpath .. "/main.cfg"
            end
            local desc = {}
            local mtl = serialize.parse(mtlpath, read_file(lfs.path(assetmgr.compile(mtlpath))))
            local keys = {}
            for k, v in pairs(mtl.properties) do
                if not v.stage then
                    keys[#keys + 1] = k
                end
            end
            table.sort(keys)
            for _, k in ipairs(keys) do
                desc[#desc + 1] = {name = k, init_value = mtl.properties[k] }
            end
            create_context.desc = desc
        end
    end
end

local ivs		= ecs.require "ant.render|visible_state"
local imaterial = ecs.require "ant.asset|material"
local bone_color = math3d.constant("v4", {0.4, 0.4, 1, 0.8})
local bone_highlight_color = math3d.constant("v4", {1.0, 0.4, 0.4, 0.8})

local ientity 	= ecs.require "ant.render|components.entity"
local imesh 	= ecs.require "ant.asset|mesh"

local function create_joint_entity(joint_name)
    local template = {
        policy = {
            "ant.render|render",
            "ant.general|name",
        },
        data = {
            scene = {},
            visible_state = "main_view|selectable",
            material = "/pkg/tools.prefab_editor/res/materials/joint.material",
            mesh = "/pkg/ant.resources.binary/meshes/base/sphere.glb|meshes/Sphere_P1.meshbin",--"/pkg/tools.prefab_editor/res/meshes/joint.meshbin",
            render_layer = "translucent",
            name = joint_name,
            on_ready = function(e)
                imaterial.set_property(e, "u_basecolor_factor", bone_color)
                ivs.set_state(e, "main_view", false)
			end
        }
    }
    return ecs.create_entity(template)
end

local bone_vert
local function create_bone_entity(joint_name)
    if not bone_vert then
		local kInter = 0.2
		local pos = {
			{1.0, 0.0, 0.0},
			{kInter, 0.1, 0.1},
			{kInter, 0.1, -0.1},
			{kInter, -0.1, -0.1},
			{kInter, -0.1, 0.1},
			{0.0, 0.0, 0.0},
		}
        local normals = {
			math3d.tovalue(math3d.normalize(math3d.cross(math3d.sub(pos[3], pos[2]), math3d.sub(pos[3], pos[1])))),
			math3d.tovalue(math3d.normalize(math3d.cross(math3d.sub(pos[2], pos[3]), math3d.sub(pos[2], pos[6])))),
			math3d.tovalue(math3d.normalize(math3d.cross(math3d.sub(pos[4], pos[3]), math3d.sub(pos[4], pos[1])))),
			math3d.tovalue(math3d.normalize(math3d.cross(math3d.sub(pos[3], pos[4]), math3d.sub(pos[3], pos[6])))),
			math3d.tovalue(math3d.normalize(math3d.cross(math3d.sub(pos[5], pos[4]), math3d.sub(pos[5], pos[1])))),
			math3d.tovalue(math3d.normalize(math3d.cross(math3d.sub(pos[4], pos[5]), math3d.sub(pos[4], pos[6])))),
			math3d.tovalue(math3d.normalize(math3d.cross(math3d.sub(pos[2], pos[5]), math3d.sub(pos[2], pos[1])))),
			math3d.tovalue(math3d.normalize(math3d.cross(math3d.sub(pos[5], pos[2]), math3d.sub(pos[5], pos[6]))))
		}
        bone_vert = {
			pos[1][1], pos[1][2], pos[1][3], normals[1][1], normals[1][2], normals[1][3], 0, 0,
        	pos[2][1], pos[2][2], pos[2][3], normals[1][1], normals[1][2], normals[1][3], 0, 0,
            pos[3][1], pos[3][2], pos[3][3], normals[1][1], normals[1][2], normals[1][3], 0, 0,
            pos[6][1], pos[6][2], pos[6][3], normals[2][1], normals[2][2], normals[2][3], 0, 0,
            pos[3][1], pos[3][2], pos[3][3], normals[2][1], normals[2][2], normals[2][3], 0, 0,
        	pos[2][1], pos[2][2], pos[2][3], normals[2][1], normals[2][2], normals[2][3], 0, 0,
        	pos[1][1], pos[1][2], pos[1][3], normals[3][1], normals[3][2], normals[3][3], 0, 0,
        	pos[3][1], pos[3][2], pos[3][3], normals[3][1], normals[3][2], normals[3][3], 0, 0,
            pos[4][1], pos[4][2], pos[4][3], normals[3][1], normals[3][2], normals[3][3], 0, 0,
            pos[6][1], pos[6][2], pos[6][3], normals[4][1], normals[4][2], normals[4][3], 0, 0,
            pos[4][1], pos[4][2], pos[4][3], normals[4][1], normals[4][2], normals[4][3], 0, 0,
        	pos[3][1], pos[3][2], pos[3][3], normals[4][1], normals[4][2], normals[4][3], 0, 0,
        	pos[1][1], pos[1][2], pos[1][3], normals[5][1], normals[5][2], normals[5][3], 0, 0,
        	pos[4][1], pos[4][2], pos[4][3], normals[5][1], normals[5][2], normals[5][3], 0, 0,
            pos[5][1], pos[5][2], pos[5][3], normals[5][1], normals[5][2], normals[5][3], 0, 0,
            pos[6][1], pos[6][2], pos[6][3], normals[6][1], normals[6][2], normals[6][3], 0, 0,
            pos[5][1], pos[5][2], pos[5][3], normals[6][1], normals[6][2], normals[6][3], 0, 0,
        	pos[4][1], pos[4][2], pos[4][3], normals[6][1], normals[6][2], normals[6][3], 0, 0,
        	pos[1][1], pos[1][2], pos[1][3], normals[7][1], normals[7][2], normals[7][3], 0, 0,
        	pos[5][1], pos[5][2], pos[5][3], normals[7][1], normals[7][2], normals[7][3], 0, 0,
            pos[2][1], pos[2][2], pos[2][3], normals[7][1], normals[7][2], normals[7][3], 0, 0,
            pos[6][1], pos[6][2], pos[6][3], normals[8][1], normals[8][2], normals[8][3], 0, 0,
            pos[2][1], pos[2][2], pos[2][3], normals[8][1], normals[8][2], normals[8][3], 0, 0,
        	pos[5][1], pos[5][2], pos[5][3], normals[8][1], normals[8][2], normals[8][3], 0, 0
		}
	end
    local template = {
		policy = {
			"ant.render|simplerender",
			"ant.general|name",
		},
		data = {
			scene 		= {},
			material	= "/pkg/tools.prefab_editor/res/materials/joint.material",
            render_layer = "translucent",
			simplemesh	= imesh.init_mesh(ientity.create_mesh({"p3|n3|t2", bone_vert}), true),
			visible_state= "main_view|selectable",
			name		= joint_name,
			on_ready 	= function(e)
                imaterial.set_property(e, "u_basecolor_factor", bone_color)
                ivs.set_state(e, "main_view", false)
			end
		}
	}
    return ecs.create_entity(template)
end

function m.on_eid_delete(eid)
    local e <close> = world:entity(eid, "material?in name:in")
    target_map[e.name] = nil
    for _, anim in pairs(allanims) do
        for _, subanim in ipairs(anim.target_anims) do
            if subanim.modifier then
                local me <close> = world:entity(subanim.modifier.eid, "modifier:in")
                if eid == me.modifier.target then
                    imodifier.set_target(subanim.modifier)
                end
            end
        end
    end
end

function m.set_current_target(target_eid)
    if current_target == target_eid then
        return
    end
    current_target = target_eid
end

function m.init(skeleton)
    for e in w:select "eid:in skeleton:in animation:in" do
        if e.skeleton == skeleton then
            anim_eid = e.eid
        end
    end
    current_skeleton = skeleton
    joint_utils.on_select_joint = function(old, new)
        if old and old.mesh then
            local e <close> = world:entity(old.mesh)
            imaterial.set_property(e, "u_basecolor_factor", bone_color)
        end
        if new then
            local e <close> = world:entity(new.mesh)
            imaterial.set_property(e, "u_basecolor_factor", bone_highlight_color)
            if current_anim then
                local layer_index = find_anim_by_name(new.name) or 0
                if layer_index ~= 0 then
                    if #current_anim.target_anims[layer_index].clips > 0 then
                        current_anim.selected_clip_index = 1
                    end
                end
                current_anim.selected_layer_index = layer_index
                current_anim.dirty = true
            end
        end
    end
    joint_utils.update_joint_pose = function(root_mat, jlist)
        if not jlist then
            return
        end
        local pose_result
        for ee in w:select "skeleton:in anim_ctrl:in" do
            if current_skeleton == ee.skeleton then
                pose_result = ee.anim_ctrl.pose_result
                break
            end
        end
        if pose_result then
            for _, joint in ipairs(jlist) do
                if joint.mesh then
                    local mesh_e <close> = world:entity(joint.mesh, "scene?in")
                    if mesh_e.scene then
                        -- joint
                        iom.set_srt_matrix(mesh_e, math3d.mul(root_mat, math3d.mul(mc.R2L_MAT, math3d.mul(pose_result:joint(joint.index), math3d.matrix{s=joint_scale}))))
                        -- bone
                        local bone_mesh_e <close> = world:entity(joint.bone_mesh, "scene?in")
                        local parent_idx = skeleton._handle:parent(joint.index)
                        local show = false
                        if parent_idx > 0 then
                            local bone_mat
                            local mat_parent = pose_result:joint(parent_idx)
                            local mat_current = pose_result:joint(joint.index)
                            local bone_dir = math3d.sub(math3d.index(mat_current, 4), math3d.index(mat_parent, 4))
                            
                            local zdir = math3d.index(mat_parent, 3)
                            local dot1 = math3d.dot(zdir, bone_dir)
                            local xdir = math3d.index(mat_parent, 1)
                            local dot2 = math3d.dot(xdir, bone_dir)
                            local binormal = math.abs(dot1) < math.abs(dot2) and zdir or xdir
                            
                            local bone_len = math3d.length(bone_dir)
                            local show_bone = bone_len > 0.0001
                            if show_bone then
                                local xaxis = bone_dir
                                local yaxis = math3d.mul(bone_len, math3d.normalize(math3d.cross(binormal, bone_dir)))
                                local zaxis = math3d.mul(bone_len, math3d.normalize(math3d.cross(bone_dir, yaxis)))
                                bone_mat = math3d.matrix(xaxis, yaxis, zaxis, math3d.index(mat_parent, 4))
                                iom.set_srt_matrix(bone_mesh_e, math3d.mul(root_mat, math3d.mul(mc.R2L_MAT, bone_mat)))
                                show = true
                            end
                            show = show_bone
                        end
                        ivs.set_state(bone_mesh_e, "main_view", show)
                    end
                end
            end
        end
    end
    local _, list = joint_utils:get_joints()
    for _, joint in ipairs(list) do
        if joint.mesh then
            w:remove(joint.mesh)
        end
    end
    joints_map, joints_list = joint_utils:init(skeleton)
    for _, joint in ipairs(joints_list) do
        if not joint.mesh then
            joint.bone_mesh = create_bone_entity(joint.name)
            joint.mesh = create_joint_entity(joint.name)
        end
    end
end

return m