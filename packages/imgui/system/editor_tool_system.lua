local ecs = ...
local world = ecs.world
local HubEvent = require "hub_event"
local fs = require "filesystem"

local editor_tool_sys = ecs.system "editor_tool_system"

local function run_script(str,env)
    local fun_str = str
    local fun,err = load(str,str,"bt",env)
    if fun then
        return fun()
    else
        error(err)
    end
end

local function on_receive_script(str)
    log.trace(str)
    local env = setmetatable( {ecs=ecs,world=world},{__index = _ENV} )
    local status,ret_val 
    if debug.getregistry()["lua-debug"] then
        ret_val =  run_script(str, env)
        status = true
    else
        status,ret_val = xpcall(run_script, debug.traceback, str, env)
    end
    if status then
        log.trace("Run script successed.\tReturn:",ret_val)
    else
        log.error("Run script failed:",ret_val)
    end
end

function editor_tool_sys:init()
    local hub = world.args.hub
    hub.subscribe(HubEvent.ETR.RunScript,on_receive_script)
end
