local lm = require "luamake"

dofile "../common.lua"
lm:import "../luabind/build.lua"
local defines = {
    "IMGUI_DISABLE_OBSOLETE_FUNCTIONS",
    "IMGUI_DISABLE_OBSOLETE_KEYIO",
    "IMGUI_DISABLE_DEBUG_TOOLS",
    "IMGUI_DISABLE_DEMO_WINDOWS",
    "IMGUI_DISABLE_DEFAULT_ALLOCATORS",
    "IMGUI_USER_CONFIG=\\\"imgui_config.h\\\"",
    lm.os == "windows" and "IMGUI_ENABLE_WIN32_DEFAULT_IME_FUNCTIONS"
}

lm:source_set "imgui" {
    windows = {
        includes = {
            ".",
            Ant3rd .. "imgui",
        },
        sources = {
            "platform/windows/imgui_platform.cpp",
            Ant3rd .. "imgui/backends/imgui_impl_win32.cpp",
        },
        defines = {
            "_UNICODE",
            "UNICODE",
            defines,
        }
    },
    macos = {
        --TODO
        deps = "sdl",
        includes = {
            ".",
            Ant3rd .. "imgui",
            Ant3rd .. "SDL/include",
        },
        sources = {
            "platform/sdl/imgui_platform.cpp",
            Ant3rd .. "imgui/backends/imgui_impl_sdl2.cpp",
        },
        defines = defines,
    },
}

lm:source_set "imgui" {
    includes = {
        ".",
        Ant3rd .. "imgui",
    },
    sources = {
        Ant3rd .. "imgui/imgui_draw.cpp",
        Ant3rd .. "imgui/imgui_tables.cpp",
        Ant3rd .. "imgui/imgui_widgets.cpp",
        Ant3rd .. "imgui/imgui.cpp",
    },
    defines = defines,
}

lm:source_set "imgui" {
    includes = {
        ".",
        Ant3rd .. "imgui",
    },
    sources = {
        "widgets/*.cpp",
    },
    defines = defines,
}

lm:source_set "imgui" {
    includes = {
        ".",
        Ant3rd .. "glm",
        Ant3rd .. "imgui",
    },
    sources = {
        "zmo/*.cpp",
    },
    defines = {
        "GLM_FORCE_QUAT_DATA_XYZW",
        defines,
    },
}

lm:lua_source "imgui" {
    deps = "luabind",
    includes = {
        ".",
        Ant3rd .. "imgui",
        Ant3rd .. "glm",
        BgfxInclude,
        "../bgfx",
        "../luabind"
    },
    sources = {
        "imgui_config.cpp",
        "imgui_renderer.cpp",
        "imgui_window.cpp",
        "luaimgui_tables.cpp",
        "luaimgui.cpp",
    },
    defines = {
        "GLM_FORCE_QUAT_DATA_XYZW",
        defines,
    },
    windows = {
        sources = {
            "platform/windows/imgui_font.cpp",
        },
        links = {
            "user32",
            "shell32",
            "ole32",
            "imm32",
            "dwmapi",
            "gdi32",
            "uuid"
        },
    },
    macos = {
        sources = {
            "platform/imgui_osx.mm",
            "platform/macos/imgui_font.mm",
        }
    }
}
