local lm = require "luamake"

dofile "../common.lua"

local TaskDir = "../../engine/task/"

lm:copy "copy_task_lua" {
    input = {
        Ant3rd .. "ltask/service/root.lua",
        Ant3rd .. "ltask/service/timer.lua",
        Ant3rd .. "ltask/service/service.lua",
    },
    output = {
        TaskDir .. "service/root.lua",
        TaskDir .. "service/timer.lua",
        TaskDir .. "service/service.lua",
    }
}

lm:lua_source "ltask" {
    deps = "copy_task_lua",
    sources = {
        Ant3rd .. "ltask/src/*.c",
        "!" .. Ant3rd .. "ltask/src/main.c",
    },
    defines = {
        --"DEBUGLOG",
        lm.mode=="debug" and "DEBUGTHREADNAME",
    },
    windows = {
        links = {
            "user32",
            "winmm",
        }
    },
    msvc = {
        ldflags = {
            "-export:luaopen_ltask",
            "-export:luaopen_ltask_bootstrap",
            "-export:luaopen_ltask_exclusive",
            "-export:luaopen_ltask_root",
        },
    },
    gcc = {
        links = "pthread",
        visibility = "default",
    },
}
