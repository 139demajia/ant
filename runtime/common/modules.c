#include "modules.h"
#include <lua.h>
#include <lauxlib.h>
#include <bgfx/c99/bgfx.h>

int luaopen_bee_filesystem(lua_State* L);
int luaopen_bee_serialization(lua_State* L);
int luaopen_bee_socket(lua_State* L);
int luaopen_bee_thread(lua_State* L);
int luaopen_bee_platform(lua_State* L);
int luaopen_bgfx(lua_State* L);
int luaopen_bgfx_util(lua_State* L);
int luaopen_crypt(lua_State* L);
int luaopen_datalist(lua_State* L);
int luaopen_hierarchy(lua_State* L);
int luaopen_math3d(lua_State* L);
int luaopen_math3d_adapter(lua_State* L);
int luaopen_platform(lua_State* L);
int luaopen_platform_timer(lua_State* L);
int luaopen_protocol(lua_State* L);
int luaopen_remotedebug(lua_State* L);
int luaopen_remotedebug_hookmgr(lua_State* L);
int luaopen_remotedebug_stdio(lua_State* L);
int luaopen_remotedebug_visitor(lua_State* L);
int luaopen_rmlui(lua_State* L);
int luaopen_rp3d_core(lua_State* L);
int luaopen_window(lua_State* L);
int luaopen_terrain(lua_State *L);
int luaopen_font(lua_State *L);
int luaopen_font_init(lua_State *L);
int luaopen_font_truetype(lua_State *L);
int luaopen_efk(lua_State* L);
int luaopen_effekseer_callback(lua_State* L);
int luaopen_audio(lua_State* L);
int luaopen_ltask(lua_State* L);
int luaopen_ltask_bootstrap(lua_State* L);
int luaopen_ltask_root(lua_State* L);
int luaopen_ltask_exclusive(lua_State* L);
int luaopen_vfs(lua_State* L);
int luaopen_ecs_core(lua_State* L);
int luaopen_fastio(lua_State* L);
int luaopen_fileinterface(lua_State *L);
int luaopen_material(lua_State *L);
int luaopen_render(lua_State *L);
int luaopen_image(lua_State* L);
#if BX_PLATFORM_IOS
int luaopen_gesture(lua_State* L);
int luaopen_ios(lua_State* L);
#endif
#if defined(ANT_RUNTIME)
int luaopen_firmware(lua_State* L);
#else
int luaopen_bee_filewatch(lua_State* L);
int luaopen_bee_subprocess(lua_State* L);
int luaopen_filedialog(lua_State* L);
int luaopen_imgui(lua_State* L);
#endif
int luaopen_system_scene(lua_State* L);
int luaopen_system_cull(lua_State* L);

void ant_loadmodules(lua_State* L) {
    static const luaL_Reg modules[] = {
        { "bee.filesystem", luaopen_bee_filesystem },
        { "bee.socket", luaopen_bee_socket },
        { "bee.serialization", luaopen_bee_serialization },
        { "bee.thread", luaopen_bee_thread },
        { "bee.platform", luaopen_bee_platform },
        { "bgfx", luaopen_bgfx },
        { "bgfx.util", luaopen_bgfx_util },
        { "font", luaopen_font },
        { "font.init", luaopen_font_init },
        { "font.truetype", luaopen_font_truetype },
        { "crypt", luaopen_crypt },
        { "datalist", luaopen_datalist },
        { "hierarchy", luaopen_hierarchy },
        { "math3d", luaopen_math3d },
        { "math3d.adapter", luaopen_math3d_adapter },
        { "platform", luaopen_platform },
        { "platform.timer", luaopen_platform_timer },
        { "protocol", luaopen_protocol },
        { "remotedebug", luaopen_remotedebug },
        { "remotedebug.hookmgr", luaopen_remotedebug_hookmgr },
        { "remotedebug.stdio", luaopen_remotedebug_stdio },
        { "remotedebug.visitor", luaopen_remotedebug_visitor },
        { "rmlui", luaopen_rmlui },
        { "rp3d.core", luaopen_rp3d_core },
        { "window", luaopen_window },
        { "terrain", luaopen_terrain},
        { "efk", luaopen_efk},
        { "effekseer.callback", luaopen_effekseer_callback},
        { "fileinterface", luaopen_fileinterface },
#if defined(_WIN32) && !defined(__MINGW32__)
        //{ "audio", luaopen_audio},
#endif
        { "ltask", luaopen_ltask},
        { "ltask.bootstrap", luaopen_ltask_bootstrap},
        { "ltask.bootstrap", luaopen_ltask_bootstrap},
        { "ltask.exclusive", luaopen_ltask_exclusive},
        { "ecs.core", luaopen_ecs_core},
        { "fastio", luaopen_fastio},
        { "render.material",    luaopen_material},
        { "render.core",        luaopen_render},
        { "image", luaopen_image },
#if BX_PLATFORM_IOS
        { "gesture", luaopen_gesture },
        { "ios", luaopen_ios },
#endif
#if defined(ANT_RUNTIME)
        { "firmware", luaopen_firmware },
#else
        { "bee.filewatch", luaopen_bee_filewatch },
        { "bee.subprocess", luaopen_bee_subprocess },
        { "filedialog", luaopen_filedialog },
        { "imgui", luaopen_imgui },
#endif
        { "system.scene", luaopen_system_scene },
        { "cull.core", luaopen_system_cull},
        { NULL, NULL },
    };

    const luaL_Reg *lib;
    luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
    for (lib = modules; lib->func; lib++) {
        lua_pushcfunction(L, lib->func);
        lua_setfield(L, -2, lib->name);
    }
    lua_pop(L, 1);

    luaL_requiref(L, "vfs", luaopen_vfs, 0);
    lua_pop(L, 1);
}
