local ecs = ...
local world = ecs.world

local fs = require "filesystem"

local assetmgr = import_package "ant.asset"

local mathpkg  = import_package "ant.math"
local mu       = mathpkg.util

local fbmgr     = require "framebuffer_mgr"
local viewidmgr = require "viewid_mgr"
local renderutil= require "util"
local computil  = require "components.util"
local uniforms  = world:interface "ant.render|uniforms"

local pps = ecs.component "postprocess_slot"
    .fb_idx         "fb_index"
    ["opt"].rb_idx  "rb_index"

function pps:init()
    self.rb_idx = self.rb_idx or 1
    return self
end

ecs.component_alias("postprocess_input",    "postprocess_slot")
ecs.component_alias("postprocess_output",   "postprocess_slot")

ecs.component "pass"
    .name           "string" ("")
    .material       "material"
    .viewport       "viewport"
    ["opt"].input   "postprocess_input"
    .output         "postprocess_output"

ecs.component "technique" {multiple=true}
    .name           "string"
    .passes         "pass[]"
    ["opt"].reorders"int[]"

ecs.component "technique_order"
    .orders "string[]"

ecs.component_alias("copy_pass", "pass")

ecs.component "postprocess"
    .techniques "int[]"
ecs.singleton "postprocess" {
    techniques = {}
}

local pp_sys = ecs.system "postprocess_system"
pp_sys.require_singleton "render_properties"
pp_sys.require_singleton "postprocess"
pp_sys.require_interface "uniforms"

pp_sys.require_system "render_system"

local quad_meshgroup

local function local_postprocess_views(num)
    local viewids = {}
    local name = "postprocess"
    for i=1, num do
        viewids[#viewids+1] = viewidmgr.get(name .. i)
    end
    return viewids
end

local postprocess_viewids = local_postprocess_views(10)

local viewid_idx = 0
local function next_viewid()
    viewid_idx = viewid_idx + 1
    return postprocess_viewids[viewid_idx]
end

local function reset_viewid_idx()
    viewid_idx = 0
end

function pp_sys:init()
    local rm = assetmgr.load("//res.mesh/postprocess.mesh", computil.quad_mesh{x=-1, y=-1, w=2, h=2})
    local _, scene = next(rm)
    local _, meshnode = next(scene)
    quad_meshgroup = meshnode[1]
end

local function is_slot_equal(lhs, rhs)
    return lhs.fb_idx == rhs.fb_idx and lhs.rb_idx == rhs.rb_idx
end

local function render_pass(lastslot, out_viewid, pass, meshgroup, render_properties)
    local ppinput_stage = uniforms.system_uniform("s_postprocess_input").stage

    local in_slot = pass.input or lastslot
    local out_slot = pass.output
    if is_slot_equal(in_slot, out_slot) then
        error(string.format("input viewid[%d:%d] is the same as output viewid[%d:%d]", 
            in_slot.viewid, in_slot.slot, out_slot.viewid, out_slot.slot))
    end

    local function bind_input(slot)
        local pp_properties = render_properties.postprocess
        local fb = fbmgr.get(slot.fb_idx)
        pp_properties.textures["s_postprocess_input"] = world:create_component("texture",
            {type="texture", stage=ppinput_stage, name="pp_input", handle=fbmgr.get_rb(fb[slot.rb_idx]).handle})
        
        pp_properties.uniforms["u_bright_threshold"] = world:create_component("uniform",
            {type = "v4", name = "bright threshold", value={0.8, 0.0, 0.0, 0.0}})
    end
    bind_input(in_slot)

    renderutil.update_frame_buffer_view(out_viewid, out_slot.fb_idx)
    renderutil.update_viewport(out_viewid, pass.viewport)

    renderutil.draw_primitive(out_viewid, {
        mgroup 	    = meshgroup,
        material 	= pass.material,
        properties  = pass.material.properties,
    }, mu.IDENTITY_MAT, render_properties)

    return out_slot
end

local function render_technique(tech, lastslot, meshgroup, render_properties)
    if tech.reorders then
        for _, passidx in ipairs(tech.reorders) do
            lastslot = render_pass(lastslot, next_viewid(), assert(tech.passes[passidx]), meshgroup, render_properties)
        end
    else
        for _, pass in ipairs(tech.passes) do
            lastslot = render_pass(lastslot, next_viewid(), pass, meshgroup, render_properties)
        end
    end

    return lastslot
end

function pp_sys:combine_postprocess()
    local pp = world:singleton "postprocess"
    local techniques = pp.techniques
    if next(techniques) then
        local render_properties = world:singleton "render_properties"
        local lastslot = {
            fb_idx = fbmgr.get_fb_idx(viewidmgr.get "main_view"),
            rb_idx = 1
        }

        reset_viewid_idx()
        for i=1, #techniques do
            local tech = techniques[i]
            lastslot = render_technique(tech, lastslot, quad_meshgroup, render_properties)
        end
    end
end

local ipp = ecs.interface "postprocess"

function ipp.main_rb_size(main_fbidx)
    main_fbidx = main_fbidx or fbmgr.get_fb_idx(viewidmgr.get "main_view")

    local fb = fbmgr.get(main_fbidx)
    local rb = fbmgr.get_rb(fb[1])
    
    assert(rb.format:match "RGBA")
    return {w=rb.w, h=rb.h}
end