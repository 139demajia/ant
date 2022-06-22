local ecs = ...
local world = ecs.world
local w = world.w

local math3d 	= require "math3d"
local start_frame_sys = ecs.system "start_frame_system"

function start_frame_sys:start_frame()
	for v in w:select "camera:in" do
		local r = v.camera
		r.viewmat = nil
		r.projmat = nil
		r.viewprojmat = nil
	end
	math3d.reset()
end
