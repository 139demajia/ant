local lm = require "luamake"

lm:lua_source "render" {
    includes = {
        "../../3rd/bgfx/include",
        "../../3rd/bx/include",
        "../../clibs/bgfx",
        "../../clibs/lua",
        "../../clibs/math3d",
    },
    sources = {
        "material/material.c",
        "material/vla.c",
        --"mesh/mesh.c",
    }
}