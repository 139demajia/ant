local ecs = ...

local init_sys = ecs.system "init_system"
local iRmlUi = ecs.require "ant.rmlui|rmlui_system"
local font = import_package "ant.font"

local function getArguments()
    return ecs.world.args.ecs.args
end
function init_sys:post_init()
    local args = getArguments()
    font.import "/pkg/ant.resources.binary/ui/test/assets/font/simsun.ttc"
    iRmlUi.set_prefix "/resource"
    local window = iRmlUi.open(args[1])
    window.addEventListener("message", function (event)
        print("Message: " .. event.data)
    end)
end


