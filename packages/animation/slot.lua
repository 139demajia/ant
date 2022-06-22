local ecs = ...
local w = ecs.world.w
local math3d = require "math3d"
local mathpkg = import_package "ant.math"
local mc = mathpkg.constant


--TODO: this file need skeleton component, should move to animation package to fix circle dependence

local r2l_mat<const> = mc.R2L_MAT

local function find_animation_entities()
    local cache = {}
    for e in w:select "scene:in id:in skeleton:in meshskin:in" do
        cache[e.id] = {
            scene       = e.scene,
            skeleton    = e.skeleton,
            pose_result = e.meshskin.pose_result,
        }
    end

    return cache
end

local sys = ecs.system "slot_system"

function sys:start_frame()
    for v in w:select "slot:in scene:in" do
		v.scene.slot_matrix = nil
	end
end

function sys:entity_init()
    for e in w:select "INIT slot:in skeleton:in" do
        local slot = e.slot
        local jn = slot.joint_name
        local ske = e.skeleton
        slot.joint_index = assert(ske._handle:joint_index(jn))
    end
end

local function calc_pose_mat(pose_result, slot)
    local adjust_mat = math3d.mul(r2l_mat, pose_result:joint(slot.joint_index))
    if slot.offset_srt then
        local offset_mat = math3d.matrix(slot.offset_srt)
        adjust_mat = math3d.mul(adjust_mat, offset_mat)
    end
    return adjust_mat
end

function sys:follow_transform_updated()
    local cache
	for v in w:select "scene:in slot:in" do
        --TODO: slot.offset_srt is duplicate with entity.scene.srt, not need to keep this srt in slot
        local slot = v.slot
        local follow_flag = assert(slot.follow_flag)
        if cache == nil then
            cache = find_animation_entities()
        end
        local e = cache[v.scene.parent]
        if e then
            local slot_matrix
            if follow_flag == 1 or follow_flag == 2 then
                if slot.joint_index then
                    local adjust_mat = calc_pose_mat(e.pose_result, slot)
                    if follow_flag == 1 then
                        slot_matrix = math3d.set_index(mc.IDENTITY_MAT, 4, math3d.index(adjust_mat, 4))
                    else
                        -- local r, t = math3d.index(adjust_mat, 3, 4)
                        -- r = math3d.torotation(r)
                        -- fixed rotation bug
                        local _, r, t = math3d.srt(adjust_mat)
                        slot_matrix = math3d.matrix{r=r, t=t}
                    end
                end
            elseif follow_flag == 3 then
                slot_matrix = calc_pose_mat(e.pose_result, slot)
            else
                error [[
                    "invalid slot, 'follow_flag' only 1/2/3 is valid
                    1: skip scale&rotation, base on parent
                    2: skip scale, base on parent
                    3: follow joint matrix. base on itself, it assume slot entity has 'pose_result' component"
                ]]
            end
            local wm = v.scene.worldmat
            wm.m = math3d.mul(wm, slot_matrix)
        end
    end

end