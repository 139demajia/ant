// A simple thread lib for lua

#define LUA_LIB

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <assert.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "simplequeue.h"
#include "simplelock.h"
#include "simplethread.h"
#include "lseri.h"

#define MAX_CHANNEL 32
#define ERRLOG_QUEUE "errlog"

#if _MSC_VER > 0
#define strdup _strdup
#endif

struct channel {
	const char * name;
	struct simple_queue *queue;
	struct thread_event trigger;
};

struct boxchannel {
	struct channel *c;
};

struct channel g_channel[MAX_CHANNEL];
int g_thread_id = 0;
LUAMOD_API int luaopen_thread(lua_State *L);

static struct channel *
new_channel_(const char * name) {
	int i;
	for (i=0;i<MAX_CHANNEL;i++) {
		if (g_channel[i].name == NULL) {
			break;
		}
	}
	struct simple_queue * q = (struct simple_queue *)malloc(sizeof(*q));
	simple_queue_init(q);
	struct channel *c = &g_channel[i];
	if (atom_cas_pointer(&c->queue, NULL, q)) {
		thread_event_create(&c->trigger);
		// name should be set at last
		atom_sync();
		c->name = strdup(name);
		return c;
	} else {
		simple_queue_destroy(q);
		free(q);
		return NULL;
	}
}

static struct channel *
new_channel(const char * name) {
	for (;;) {
		if (g_channel[MAX_CHANNEL-1].name != NULL) {
			return NULL;
		}
		struct channel *c = new_channel_(name);
		if (c)
			return c;
	}
}

static struct channel *
query_channel(const char *name) {
	int i;
	for (i=0;i<MAX_CHANNEL;i++) {
		if (g_channel[i].name == NULL) {
			return NULL;
		}
		if (strcmp(g_channel[i].name, name)==0) {
			return &g_channel[i];
		}
	}
	return NULL;
}

static int
lnewchannel(lua_State *L) {
	const char * name = luaL_checkstring(L, 1);
	struct channel * c = new_channel(name);
	if (c == NULL)
		return luaL_error(L, "Can't create channel %s", name);
	struct channel * q = query_channel(name);
	if (q != c)
		return luaL_error(L, "Duplicate channel %s", name);
	return 0;
}

static void
push_channel(struct channel *c, struct simple_queue_slot *slot) {
	simple_queue_push(c->queue, slot);
	thread_event_trigger(&c->trigger);
}

static int
lpush(lua_State *L) {
	struct boxchannel * bc = luaL_checkudata(L, 1, "THREAD_PRODUCE");
	struct channel *c = bc->c;
	void * buffer = seri_pack(L, 1, NULL);
	struct simple_queue_slot slot = { buffer };
	push_channel(c, &slot);
	return 0;
}

// return 1: pop, 0: timeout
static int
timed_pop(lua_State *L, struct channel *c, struct simple_queue_slot *slot, int timeout) {
	if (simple_queue_pop(c->queue, slot)) {
		thread_event_wait(&c->trigger, timeout);
		if (simple_queue_pop(c->queue, slot)) {
			// queue is empty (rare condition, multi consumer)
			return 0;
		}
	}
	return 1;
}

static int
lblockedpop(lua_State *L) {
	struct boxchannel * bc = luaL_checkudata(L, 1, "THREAD_CONSUME");
	struct channel *c = bc->c;
	struct simple_queue_slot slot;
	while(!timed_pop(L, c, &slot, -1)) {};
	int n = seri_unpackptr(L, slot.data);
	return n;
}

static int
lpop(lua_State *L) {
	struct boxchannel * bc = luaL_checkudata(L, 1, "THREAD_CONSUME");
	struct channel *c = bc->c;
	struct simple_queue_slot slot;
	if (simple_queue_pop(c->queue, &slot)) {
		// queue is empty
		lua_settop(L, 2);
		lua_Number v = lua_tonumber(L, 2);
		if (v != 0) {
			int timeout = (int)(v * 1000);
			if (!timed_pop(L, c, &slot, timeout)) {
				return 0;
			}
		} else {
			// No 2nd arg or timeout == 0, don't wait
			return 0;
		}
	}
	lua_pushboolean(L, 1);
	int n = seri_unpackptr(L, slot.data);
	return n+1;
}

static int
lpchannel(lua_State *L) {
	const char * name = luaL_checkstring(L, 1);
	struct channel * c = query_channel(name);
	if (c == NULL)
		return luaL_error(L, "Can't query channel %s", name);

	struct boxchannel *bc = lua_newuserdatauv(L, sizeof(*bc), 0);
	bc->c = c;
	if (luaL_newmetatable(L, "THREAD_PRODUCE")) {
		luaL_Reg l[] = {
			{ "push", lpush },
			{ NULL, NULL },
		};
		luaL_setfuncs(L, l, 0);
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, lpush);
		lua_setfield(L, -2, "__call");
	}
	lua_setmetatable(L, -2);
	return 1;
}

static int
lcchannel(lua_State *L) {
	const char * name = luaL_checkstring(L, 1);
	struct channel * c = query_channel(name);
	if (c == NULL)
		return luaL_error(L, "Can't query channel %s", name);

	struct boxchannel *bc = lua_newuserdatauv(L, sizeof(*bc), 0);
	bc->c = c;
	if (luaL_newmetatable(L, "THREAD_CONSUME")) {
		luaL_Reg l[] = {
			{ "pop", lpop },
			{ "bpop", lblockedpop },
			{ NULL, NULL },
		};
		luaL_setfuncs(L, l, 0);
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, lblockedpop);
		lua_setfield(L, -2, "__call");
	}
	lua_setmetatable(L, -2);
	return 1;
}

static int
lsleep(lua_State *L) {
	lua_Number sec = luaL_checknumber(L, 1);
	int msec = (int)(sec * 1000);
	thread_sleep(msec);
	return 0;
}

struct thread_args {
	char * source;
	size_t sz;
	lua_CFunction param;
};

static void
thread_args_free(struct thread_args *args) {
	free(args->source);
	free(args);
}

static int luaopen_thread_worker(lua_State *L);

static int
thread_luamain(lua_State *L) {
	lua_pushboolean(L, 1);
	lua_setfield(L, LUA_REGISTRYINDEX, "LUA_NOENV");
	luaL_openlibs(L);
	lua_gc(L, LUA_GCGEN, 0, 0);
	int id = atom_inc(&g_thread_id);
	lua_pushinteger(L, id);
	lua_setfield(L, LUA_REGISTRYINDEX, "THREADID");
	// todo: preload thread, and prevent dlclose thread.dll
	//	luaL_requiref(L, "thread", luaopen_thread_worker, 0);
	void *ud = lua_touserdata(L, 1);
	struct thread_args *args = (struct thread_args *)ud;
	if (luaL_loadbuffer(L, args->source, args->sz, "=(thread init)") != LUA_OK) {
		thread_args_free(args);
		return lua_error(L);
	}
	lua_CFunction f = args->param;
	thread_args_free(args);
	if (f == NULL) {
		lua_call(L, 0, 0);
	} else {
		lua_pushcfunction(L, f);
		lua_call(L, 1, 0);
	}
	return 0;
}

static int
msghandler(lua_State *L) {
	const char *msg = lua_tostring(L, 1);
	if (msg == NULL) {  /* is error object not a string? */
		if (luaL_callmeta(L, 1, "__tostring") &&  /* does it have a metamethod */
			lua_type(L, -1) == LUA_TSTRING)  /* that produces a string? */
			return 1;  /* that is the message */
		else
			msg = lua_pushfstring(L, "(error object is a %s value)",
								   luaL_typename(L, 1));
	}
	luaL_traceback(L, L, msg, 1);  /* append a standard traceback */
	return 1;  /* return the traceback */
}

static void *
thread_main(void *ud) {
	lua_State *L = luaL_newstate();
	lua_pushcfunction(L, msghandler);
	lua_pushcfunction(L, thread_luamain);
	lua_pushlightuserdata(L, ud);
	if (lua_pcall(L, 1, 0, 1) != LUA_OK) {
		// NOTICE: may memory leak when error (ud may not be free)
		struct channel * errlog = query_channel(ERRLOG_QUEUE);
		if (errlog) {
			size_t sz;
			const char * str = lua_tolstring(L, -1, &sz);
			void * errmsg = seri_packstring(str, (int)sz);
			struct simple_queue_slot slot = { errmsg };
			push_channel(errlog, &slot);
		} else {
			printf("thread error : %s", lua_tostring(L, -1));
		}
	}
	lua_close(L);
	return NULL;
}

static struct thread_args *
thread_args_new(lua_State *L, int idx) {
	size_t sz;
	const char * source = luaL_checklstring(L, idx, &sz);
	lua_CFunction f;
	if (lua_isnoneornil(L, idx+1)) {
		f = NULL;
	} else {
		if (!lua_iscfunction(L,idx+1) || lua_getupvalue(L,idx+1,1) != NULL) {
			luaL_error(L, "2nd param should be a C function without upvalue");
			return NULL;
		}
		f = lua_tocfunction(L, idx+1);
	}
	struct thread_args *args = (struct thread_args *)malloc(sizeof(*args));
	args->source = (char *)malloc(sz + 1);
	memcpy(args->source, source, sz + 1);
	args->sz = sz;
	args->param = f;
	return args;
}

/*
	string source code
	cfunction param

	return lightuserdata
 */
static int
lthread(lua_State *L) {
	struct thread_args * args = thread_args_new(L, 1);
	struct thread th = { thread_main, args };
	if (thread_create(&th)) {
		thread_args_free(args);
		return luaL_error(L, "Create thread failed");
	}
	lua_pushlightuserdata(L, th.id);
	return 1;
}

static void *
thread_fork(void *ud) {
	lua_State *L = (lua_State *)ud;
	lua_pushcfunction(L, msghandler);
	lua_insert(L, 1);
	// stack : msghandler func
	if (lua_pcall(L, 0, LUA_MULTRET, 1) != LUA_OK) {
		lua_replace(L, 1);
		// return error string
	}
	// return multi values

	return NULL;
}

/*
	function run this function in a new thread
	string source code , load into a new vm and run in current vm
	cfunction param

	return ... ( return values from fork function)
 */
static int
lfork(lua_State *L) {
	// save args
	struct thread_args *args = thread_args_new(L, 2);
	luaL_checktype(L, 1, LUA_TFUNCTION);
	lua_settop(L, 1);

	// run function in a new thread
	struct thread th = { thread_fork, L };
	if (thread_create(&th)) {
		thread_args_free(args);
		return luaL_error(L, "Fork failed");
	}

	// run source in current thread

	thread_main(args);

	// wait for fork function end
	thread_wait(th.id);

	if (lua_type(L, 1) == LUA_TSTRING) {
		lua_settop(L, 1);
		lua_error(L);
	}

	return lua_gettop(L) - 1;
}

static int
lwait(lua_State *L) {
	luaL_checktype(L, 1, LUA_TLIGHTUSERDATA);
	void * pid = lua_touserdata(L, 1);
	thread_wait(pid);
	return 0;
}

static void
delete_channel(struct channel *c) {
	struct channel tmp = *c;
	memset(c, 0, sizeof(*c));
	if (tmp.name) {
		free((char *)tmp.name);
		simple_queue_destroy(tmp.queue);
		free(tmp.queue);
		thread_event_release(&tmp.trigger);
	}
}

static int
lreset(lua_State *L) {
	lua_getfield(L, LUA_REGISTRYINDEX, "THREADID");
	int threadid = (int)lua_tointeger(L, -1);
	lua_pop(L, 1);
	if (threadid != 0) {
		return luaL_error(L, "reset must call from main thread");
	}

	int i;
	for (i=0;i<MAX_CHANNEL;i++) {
		delete_channel(&g_channel[i]);
	}
	g_thread_id = 0;
	lua_pushcfunction(L, lnewchannel);
	lua_pushstring(L, ERRLOG_QUEUE);
	lua_call(L, 1, 0);

	return 0;
}

static int
lpack(lua_State *L) {
	int sz = 0;
	void * buffer = seri_pack(L, 0, &sz);
	lua_pushlstring(L, buffer, sz);
	free(buffer);
	return 1;
}

static int
luaopen_thread_worker(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "sleep", lsleep },
		{ "thread", lthread },
		{ "fork", lfork },
		{ "wait", lwait },
		{ "newchannel", lnewchannel },
		{ "channel_consume", lcchannel },
		{ "channel_produce", lpchannel },
		{ "reset", lreset },
		{ "pack", lpack },
		{ "unpack", seri_unpack },
		{ NULL, NULL },
	};
	luaL_newlib(L,l);
	if (lua_getfield(L, LUA_REGISTRYINDEX, "THREADID") != LUA_TNUMBER) {
		return luaL_error(L, "No THREADID in registry");
	}
	lua_setfield(L, -2, "id");
	return 1;
}

LUAMOD_API int
luaopen_thread(lua_State *L) {
	if (lua_getfield(L, LUA_REGISTRYINDEX, "THREADID") == LUA_TNIL) {
		lua_pop(L, 1);
		if (g_thread_id > 0 || query_channel(ERRLOG_QUEUE)) {
			// In a sub VM (not in a child thread created by this module)
			int id = atom_inc(&g_thread_id);
			lua_pushinteger(L, id);
		} else {
			lua_pushcfunction(L, lnewchannel);
			lua_pushstring(L, ERRLOG_QUEUE);
			lua_call(L, 1, 0);
			assert(g_thread_id == 0);
			lua_pushinteger(L, 0);
		}
		lua_setfield(L, LUA_REGISTRYINDEX, "THREADID");
	} else {
		lua_pop(L,1);
	}
	return luaopen_thread_worker(L);
}
