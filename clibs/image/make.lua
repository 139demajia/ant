local lm = require "luamake"

dofile "../common.lua"

lm:lua_source "image" {
    deps = {
        "bimg-decode",
        "bimg",
        "bx",
    },
    defines = "BX_CONFIG_DEBUG=" .. (lm.mode == "debug" and 1 or 0),
    includes = {
        BgfxInclude,
        Ant3rd .. "bimg/include",
        Ant3rd .. "glm",
        "../bgfx",
        "../luabind",
    },
    sources = {
        "image.cpp",
    },
}
