local lm = require "luamake"
local fs = require "bee.filesystem"

local runtime = false

local RuntimeBacklist = {
    filedialog = true,
    imgui = true,
    effekseer = true,
    remotedebug = true,
}

local EditorBacklist = {
    firmware = true,
    effekseer = true,
    remotedebug = true,
}

local RuntimeModules = {}
local EditorModules = {}

local function checkAddModule(name, makefile)
    if not RuntimeBacklist[name] or not EditorBacklist[name] then
        lm:import(makefile)
    end
    if lm:has(name) then
        if not RuntimeBacklist[name] then
            RuntimeModules[#RuntimeModules + 1] = name
        end
        if not EditorBacklist[name] then
            EditorModules[#EditorModules + 1] = name
        end
    end
end

for path in fs.pairs(fs.path(lm.workdir) / "../clibs") do
    if fs.exists(path / "make.lua") then
        local name = path:stem():string()
        local makefile = ("../clibs/%s/make.lua"):format(name)
        checkAddModule(name, makefile)
    end
end

for path in fs.pairs(fs.path(lm.workdir) / "../pkg") do
    if fs.exists(path / "make.lua") then
        local name = path:filename():string()
        local makefile = ("../pkg/%s/make.lua"):format(name)
        checkAddModule(name:sub(5, -1), makefile)
    end
end

lm:copy "copy_mainlua" {
    input = "common/main.lua",
    output = "../"..lm.bindir,
}

lm:lua_source "ant_common" {
    deps = "lua_source",
    includes = {
        "../3rd/bgfx/include",
        "../3rd/bx/include",
        "common"
    },
    sources = {
        "common/runtime.cpp",
        "common/progdir.cpp",
    },
    windows = {
        sources = "windows/main.cpp",
    },
    macos = {
        sources = "osx/main.cpp",
    },
    ios = {
        includes = "../../clibs/window/ios",
        sources = {
            "common/ios/main.mm",
            "common/ios/ios_error.mm",
        }
    }
}
lm:lua_source "ant_openlibs" {
    sources = "common/ant_openlibs.c",
}

lm:source_set "ant_links" {
    windows = {
        links = {
            "shlwapi",
            "user32",
            "gdi32",
            "shell32",
            "ole32",
            "oleaut32",
            "wbemuuid",
            "winmm",
            "ws2_32",
            "imm32",
            "advapi32",
            "version",
        }
    },
    macos = {
        frameworks = {
            "Carbon",
            "IOKit",
            "Foundation",
            "Metal",
            "QuartzCore",
            "Cocoa"
        }
    },
    ios = {
        frameworks = {
            "CoreTelephony",
            "SystemConfiguration",
            "Foundation",
            "CoreText",
            "UIKit",
            "Metal",
            "QuartzCore",
            "IOSurface",
            "CoreGraphics"
        },
        ldflags = {
            "-fembed-bitcode",
            "-fobjc-arc"
        }
    },
    android = {
        links = {
            "android",
            "log",
            "m",
        }
    }
}

lm:lua_source "ant_runtime" {
    deps = {
        "ant_common",
        RuntimeModules,
    },
    includes = {
        "../3rd/bgfx/include",
        "../3rd/bx/include",
    },
    defines = "ANT_RUNTIME",
    sources = "common/modules.c",
}

lm:lua_source "ant_editor" {
    deps = {
        "ant_common",
        EditorModules,
    },
    includes = {
        "../3rd/bgfx/include",
        "../3rd/bx/include",
    },
    sources = {
        "common/modules.c",
    },
}

if lm.os == "android" then
    lm:dll "ant" {
        deps = {
            "ant_runtime",
            "ant_openlibs",
            "bgfx-lib",
            "ant_links",
            "copy_mainlua"
        }
    }
    lm:phony "runtime" {
        deps = "ant"
    }
    return
end

lm:exe "lua" {
    deps = {
        "ant_editor",
        "ant_openlibs",
        "bgfx-lib",
        "ant_links",
        "copy_mainlua"
    },
    msvc = {
        sources = "windows/lua.rc",
    },
    mingw = {
        sources = "windows/lua.rc",
    }
}

lm:exe "ant" {
    deps = {
        "ant_runtime",
        "ant_openlibs",
        "bgfx-lib",
        "ant_links",
        "copy_mainlua"
    },
    msvc = {
        sources = "windows/lua.rc",
    },
    mingw = {
        sources = "windows/lua.rc",
    }
}

lm:phony "editor" {
    deps = "lua"
}

lm:phony "runtime" {
    deps = "ant"
}