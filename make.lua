local lm = require "luamake"

local plat = (function ()
    if lm.os == "windows" then
        if lm.compiler == "gcc" then
            return "mingw"
        end
        return "msvc"
    end
    return lm.os
end)()

lm.mode = "debug"
lm.builddir = ("build/%s/%s"):format(plat, lm.mode)
lm.bindir = ("bin/%s/%s"):format(plat, lm.mode)
lm.compile_commands = "build"

local EnableEditor = true
if lm.os == "ios" then
    lm.arch = "arm64"
    EnableEditor = false
    if lm.mode == "release" then
        lm.sys = "ios14.1"
    else
        lm.sys = "ios14.1"
    end
end

lm.c = "c11"
lm.cxx = "c++20"
lm.msvc = {
    defines = "_CRT_SECURE_NO_WARNINGS",
    flags = {
        "-wd5105"
    }
}

if lm.mode == "release" then
    lm.msvc.ldflags = {
        "/DEBUG:FASTLINK"
    }
end

lm.ios = {
    flags = {
        "-fembed-bitcode",
        "-fobjc-arc"
    }
}

--TODO
lm.visibility = "default"

lm:import "3rd/scripts/bgfx.lua"
lm:import "3rd/scripts/ozz-animation.lua"
lm:import "3rd/scripts/reactphysics3d.lua"
lm:import "3rd/scripts/sdl.lua"
lm:import "runtime/make.lua"

local function compile_ecs(editor)
    local args = {
        "@packages/ecs/component.lua",
        "@clibs/ecs/ecs/",
        "@packages",
    }
    local inputs = {
        "packages/**/*.ecs"
    }
    if editor then
        inputs[#inputs+1] = "tools/prefab_editor/**/*.ecs"
        args[#args+1] = "@tools/prefab_editor/"
    end
    lm:runlua "compile_ecs" {
        script = "projects/luamake/ecs.lua",
        args = args,
        inputs = inputs,
        output = {
            "packages/ecs/component.lua",
            "clibs/ecs/ecs/component.h",
            "clibs/ecs/ecs/component.hpp",
        }
    }
    
end

if EnableEditor then
    compile_ecs(true)
    lm:phony "tools" {
        deps = {
            "gltf2ozz",
            "shaderc",
            "texturec",
        }
    }
    lm:phony "all" {
        deps = {
            "editor",
            "runtime",
            "tools",
        }
    }
    lm:default "editor"
else
    compile_ecs()
    lm:default "runtime"
end
