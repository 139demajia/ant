#define LUA_LIB

#include <stdio.h>
#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include <lua-seri.h>
#include "window.h"
#include "virtual_keys.h"
#ifdef _WIN32
#include <windows.h>
#include <WinNT.h>
#endif //_WIN32


struct callback_context {
	lua_State *callback;
	lua_State *functions;
	int surrogate;
};

static int
push_callback_function(struct callback_context * context, int id) {
	lua_pushvalue(context->functions, 1);
	lua_pushvalue(context->functions, id + 1);
	lua_xmove(context->functions, context->callback, 2);
	int ret = lua_type(context->callback, 3) == LUA_TSTRING;
	if (!ret) {
		lua_pop(context->callback, 2);
	}
	return ret;
}

static void
push_update_args(lua_State *L, struct ant_window_update *update) {
}

static void
push_init_args(lua_State *L, struct ant_window_init *init) {
	lua_pushlightuserdata(L, init->window);
	lua_pushlightuserdata(L, init->context);
	lua_pushinteger(L, init->w);
	lua_pushinteger(L, init->h);
}

static void
push_exit_args(lua_State *L, struct ant_window_exit *exit) {
}

static void
push_touch_args(lua_State *L, struct ant_window_touch *touch) {
    seri_unpackptr(L, touch->data);
}

static void
push_keyboard_arg(lua_State *L, struct ant_window_keyboard *keyboard) {
	lua_pushinteger(L, keyboard->key);
	lua_pushinteger(L, keyboard->press);
	lua_pushinteger(L, keyboard->state);
}

static void
push_mouse_wheel_args(lua_State *L, struct ant_window_mouse_wheel *mouse) {
	lua_pushinteger(L, mouse->x);
	lua_pushinteger(L, mouse->y);
	lua_pushnumber(L, mouse->delta);
}

static void
push_mouse_arg(lua_State *L, struct ant_window_mouse *mouse) {
	lua_pushinteger(L, mouse->x);
	lua_pushinteger(L, mouse->y);
	lua_pushinteger(L, mouse->type);
	lua_pushinteger(L, mouse->state);
}

static void
push_size_arg(lua_State *L, struct ant_window_size *size) {
	lua_pushinteger(L, size->x);
	lua_pushinteger(L, size->y);
	lua_pushinteger(L, size->type);
}

static void
push_char_arg(lua_State *L, struct ant_window_char *c) {
	lua_pushinteger(L, c->code);
}

static int
push_arg(lua_State *L, struct ant_window_message *msg) {
	switch(msg->type) {
	case ANT_WINDOW_UPDATE:
		push_update_args(L, &msg->u.update);
		break;
	case ANT_WINDOW_INIT:
	case ANT_WINDOW_RECREATE:
		push_init_args(L, &msg->u.init);
		break;
	case ANT_WINDOW_EXIT:
		push_exit_args(L, &msg->u.exit);
		break;
	case ANT_WINDOW_TOUCH:
		push_touch_args(L, &msg->u.touch);
		break;
	case ANT_WINDOW_KEYBOARD:
		push_keyboard_arg(L, &msg->u.keyboard);
		break;
	case ANT_WINDOW_MOUSE_WHEEL:
		push_mouse_wheel_args(L, &msg->u.mouse_wheel);
		break;
	case ANT_WINDOW_MOUSE:
		push_mouse_arg(L, &msg->u.mouse);
		break;
	case ANT_WINDOW_SIZE:
		push_size_arg(L, &msg->u.size);
		break;
	case ANT_WINDOW_CHAR:
		push_char_arg(L, &msg->u.unichar);
		break;
	default:
		return 0;
	}
	return 1;
}

static void
message_callback(void *ud, struct ant_window_message *msg) {
	if (!ud) {
		return;
	}
	struct callback_context * context = (struct callback_context *)ud;
	lua_State *L = context->callback;
	if (!push_callback_function(context, msg->type) || !push_arg(L, msg)) {
		return;
	}
	int nargs = lua_gettop(L) - 2;
	if (lua_pcall(L, nargs, 0, 1) != LUA_OK) {
		printf("Error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
}

static void
register_function(lua_State *L, const char *name, lua_State *fL, int id) {
	lua_pushstring(L, name);
	lua_xmove(L, fL, 1);
	lua_replace(fL, id + 1);
}

static void
register_functions(lua_State *L, int index, lua_State *fL) {
	lua_pushvalue(L, index);
	lua_xmove(L, fL, 1);

	luaL_checkstack(fL, ANT_WINDOW_COUNT+3, NULL);	// 3 for temp
	for (int i = 0; i < ANT_WINDOW_COUNT; ++i) {
		lua_pushnil(fL);
	}
	register_function(L, "update", fL, ANT_WINDOW_UPDATE);
	register_function(L, "init", fL, ANT_WINDOW_INIT);
	register_function(L, "exit", fL, ANT_WINDOW_EXIT);
	register_function(L, "touch", fL, ANT_WINDOW_TOUCH);
	register_function(L, "keyboard", fL, ANT_WINDOW_KEYBOARD);
	register_function(L, "mouse_wheel", fL, ANT_WINDOW_MOUSE_WHEEL);
	register_function(L, "mouse", fL, ANT_WINDOW_MOUSE);
	register_function(L, "size", fL, ANT_WINDOW_SIZE);
	register_function(L, "char", fL, ANT_WINDOW_CHAR);
}

static int
ltraceback(lua_State *L) {
	const char *msg = lua_tostring(L, 1);
	if (msg == NULL && !lua_isnoneornil(L, 1)) {
		lua_pushvalue(L, 1);
	} else {
		luaL_traceback(L, L, msg, 2);
	}
	return 1;
}

static struct ant_window_callback*
get_callback(lua_State *L) {
	if (lua_getfield(L, LUA_REGISTRYINDEX, ANT_WINDOW_CALLBACK) != LUA_TUSERDATA) {
		luaL_error(L, "Can't find ant_window_callback.");
		return 0;
	}
	return (struct ant_window_callback*)lua_touserdata(L, -1);
}

static int registercallback(lua_State *L, struct ant_window_callback* cb) {
	luaL_checktype(L, 1, LUA_TFUNCTION);

	struct callback_context * context = lua_newuserdatauv(L, sizeof(*context), 2);
	context->surrogate = 0;
	context->callback = lua_newthread(L);
	lua_setiuservalue(L, -2, 1);
	context->functions = lua_newthread(L);
	lua_setiuservalue(L, -2, 2);
	lua_setfield(L, LUA_REGISTRYINDEX, "ANT_WINDOW_CONTEXT");

	lua_pushcfunction(context->callback, ltraceback);	// push traceback function
	register_functions(L, 1, context->functions);

	cb->message = message_callback;
	cb->ud = context;
	return 0;
}

static int
lcreate(lua_State *L) {
	struct ant_window_callback* cb = lua_newuserdatauv(L, sizeof(*cb), 1);
	cb->ud = NULL;
	cb->message = message_callback;
	cb->L = lua_newthread(L);
	lua_setiuservalue(L, -2, 1);
	lua_setfield(L, LUA_REGISTRYINDEX, ANT_WINDOW_CALLBACK);
	registercallback(L, cb);
	if (0 != window_init(cb)) {
		return luaL_error(L, "Create window failed");
	}
	lua_pushboolean(L, 1);
	return 1;
}

static int
lmainloop(lua_State *L) {
	int update = lua_toboolean(L, 1);
	window_mainloop(get_callback(L), update);
	return 0;
}

LUAMOD_API int
luaopen_window(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "create", lcreate },
		{ "mainloop", lmainloop },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	return 1;
}
