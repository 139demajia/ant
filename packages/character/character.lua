local ecs = ...
local world = ecs.world

local math3d = require "math3d"
local mc = import_package "ant.math".constant

local char_height_sys = ecs.system "character_height_system"

local icollider = world:interface "ant.collision|collider"

local character_motion = world:sub {"character_motion"}
local character_spawn = world:sub {"component_register", "character"}

local function generate_height_test_ray(e)
    local height_raycast = e.character_height_raycast
    local c_aabb_min, c_aabb_max = icollider(e)

    if c_aabb_min and c_aabb_max then
        local center = math3d.totable(math3d.mul(0.5, math3d.add(c_aabb_min, c_aabb_max)))
        local startpt = math3d.vector(center[1], c_aabb_min[2], center[2], 1.0)
        local endpt = math3d.add(startpt, height_raycast.dir)
        return {
            startpt, endpt,
        }
    end
end

function char_height_sys:do_ik()
    for _, eid in world:each "character_height_raycast" do
        local e = world[eid]

        local ray = generate_height_test_ray(e)
        if ray then
            icollider.raycast(ray[1], ray[2])
        end
    end
end

local foot_t = ecs.transform "check_ik_data"

function foot_t.process_prefab(e)
    local r = e.foot_ik_raycast
    local ik = e.ik

    local trackers = r.trackers
    local jobs = ik.jobs
    for _, tracker in ipairs(trackers) do
        local leg_ikdata = jobs[tracker.leg]
        if leg_ikdata == nil then
            error(string.format("foot_ik_raycast.ik_job_name:%s, not found in ik component", r.ik_job_name))
        end

        if leg_ikdata.type ~= "two_bone" then
            error(string.format("leg ik job must be two_bone:%s", leg_ikdata.type))
        end

        local joint_indices = leg_ikdata._joint_indices
        if #joint_indices ~= 3 then
            error(string.format("joints number must be 3 for two_bone ik type, %d provided", #joint_indices))
        end

        -----
        local sole_name = tracker.sole
        if sole_name then
            local sole_ikdata = jobs[tracker.sole]
            if sole_ikdata == nil then
                error(string.format("invalid ik job name:%s", tracker.sole))
            end

            if sole_ikdata.type ~= "aim" then
                error(string.foramt("sole ik job must aim type:%s", sole_ikdata.type))
            end

            local sole_joint_indices = sole_ikdata._joint_indices
            if #sole_joint_indices ~= 1 then
                error(string.format("joints number must be 1 for aim ik type, %d provided", #sole_joint_indices))
            end

            if joint_indices[3] ~= sole_joint_indices[1] then
                error(string.format("we assume leg last joint is equal to sole joint"))
            end
        end
    end
end

local char_foot_ik_sys = ecs.system "character_foot_ik_system"

local iik = world:interface "ant.animation|ik"

local function ankles_raycast_ray(ankle_pos_ws, dir)
    return {
        ankle_pos_ws,
        math3d.add(ankle_pos_ws, dir),
    }
end

local function ankles_target(ray, foot_height)
    local pos, normal, id = icollider.raycast(ray)
    if pos then
        return math3d.muladd(normal, foot_height, pos), normal, id
    end
end

local function calc_pelvis_offset(leg_raycasts, cast_dir)
    local normalize_cast_dir = math3d.normalize(cast_dir)
    local max_dot
    local offset = mc.ZERO_PT
    for _, l in ipairs(leg_raycasts) do
        local ankle_pos, target_pos = l[2], l[3]

        local dot = math3d.dot(normalize_cast_dir, math3d.sub(target_pos, ankle_pos))
        if max_dot == nil or dot > max_dot then
            max_dot = dot
            offset = math3d.mul(normalize_cast_dir, dot)
        end
    end

    return offset
end

local function refine_target(raystart, hitpt, hitnormal, foot_height)
    -- see ozz-animation samples:sample_foot_ik.cc:UpdateAnklesTarget for commonet
    local ABl = math3d.dot(math3d.sub(raystart, hitpt), hitnormal)
    if ABl ~= 0 then
        local ptB = math3d.sub(raystart, math3d.mul(hitnormal, ABl))
        local IB = math3d.sub(ptB, hitpt)
        local IBl = math3d.length(IB)

        if IBl <= 0 then
            return math3d.muladd(hitnormal, foot_height, hitpt)
        end

        local IHl = IBl * foot_height / ABl
        local H = math3d.muladd(IB, IHl / IBl, hitpt)
        return math3d.muladd(hitnormal, foot_height, H)
    end

    return hitpt
end

local function find_leg_raycast_target(pose_result, ik, foot_rc, trans)
    local leg_raycasts = {}
    local cast_dir = foot_rc.cast_dir
    local foot_height = foot_rc.foot_height
    local jobs = ik.jobs
    for _, tracker in ipairs(foot_rc.trackers) do
        local leg_ikdata = jobs[tracker.leg]
        local anklenidx = leg_ikdata._joint_indices[3]
        local jointmat = pose_result:joint(anklenidx)
        local ankle_pos = math3d.index(jointmat, 4)
        local ispoint<const> = 1
        local ankle_pos_ws = math3d.transform(trans, ankle_pos, ispoint)

        local castray = ankles_raycast_ray(ankle_pos_ws, cast_dir)
        local target_ws, hitnormal_ws, id = ankles_target(castray, foot_height)
        if target_ws then
            target_ws = refine_target(castray[1], target_ws, hitnormal_ws, foot_height)
            leg_raycasts[#leg_raycasts+1] = {
                tracker, ankle_pos_ws, target_ws, hitnormal_ws
            }
        end
    end

    return leg_raycasts
end

local function do_foot_ik(pose_result, ik, inv_trans, leg_raycasts)
    local function joint_y_vector(jointidx)
        local m = pose_result:joint(jointidx)
        return math3d.index(m, 2)
    end
    local jobs = ik.jobs
    for _, leg in ipairs(leg_raycasts) do
        local tracker = leg[1]
        local leg_ikdata = jobs[tracker.leg]
        local sole_ikdata = tracker.sole and jobs[tracker.sole] or nil

        local target_ws = leg[3]
        leg_ikdata.target.v = math3d.transform(inv_trans, target_ws, nil)

        local knee = leg_ikdata._joint_indices[2]
        leg_ikdata.pole_vector.v = joint_y_vector(knee)

        iik.do_ik(pose_result, leg_ikdata)

        if sole_ikdata then
            local hitnormal = leg[4]
            sole_ikdata.target.v = math3d.transform(inv_trans, math3d.add(target_ws, hitnormal), 1)
            sole_ikdata.pole_vector.v = joint_y_vector(sole_ikdata._joint_indices[1])
            iik.do_ik(pose_result, sole_ikdata)
        end
    end
end

local itransform = world:interface "ant.scene|itransform"

function char_foot_ik_sys:do_ik()
    for _, eid in world:each "foot_ik_raycast" do
        local e = world[eid]
        local foot_rc = e.foot_ik_raycast
        
        local ik = e.ik
        local pose_result = e.pose_result
        local worldmat = itransform.worldmat(eid)

        local leg_raycasts = find_leg_raycast_target(pose_result, ik, foot_rc, worldmat)

        if next(leg_raycasts) then
            iik.setup(e)
            local pelvis_offset = calc_pelvis_offset(leg_raycasts, foot_rc.cast_dir)
            local correct_trans = math3d.mul(worldmat, math3d.matrix{t=pelvis_offset})
            local inv_correct_trans = math3d.inverse(correct_trans)

            do_foot_ik(pose_result, ik, inv_correct_trans, leg_raycasts)
        end
    end

end