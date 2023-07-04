#include <lua.hpp>
#include <binding/luaplugin.h>
#include <binding/luabind.h>
#include <databinding/DataModel.h>
#include <databinding/DataVariable.h>
#include <core/Element.h>
#include <core/Document.h>

struct LuaPushVariantVisitor {
	lua_State* L;
	void operator()(float const& p) {
		lua_pushnumber(L, p);
	}
	void operator()(int const& p) {
		lua_pushinteger(L, p);
	}
	void operator()(std::string const& p) {
		lua_pushlstring(L, p.c_str(), p.length());
	}
	void operator()(bool const& p) {
		lua_pushboolean(L, p);
	}
	void operator()(std::monostate const& p) {
		lua_pushnil(L);
	}
};

void
lua_pushvariant(lua_State *L, const Rml::DataVariant& variant) {
	luavalue::get(L, variant);
}

void
lua_getvariant(lua_State *L, int index, Rml::DataVariant* variant) {
	if (!variant)
		return;
	luavalue::set(L, index, *variant);
}

class LuaScalarDef;
class LuaTableDef;

struct LuaDataModel {
	Rml::DataModel* datamodel;
	LuaScalarDef *scalarDef;
	LuaTableDef* tableDef;
	lua_State* dataL;
	int top;
	LuaDataModel(Rml::Document* document);
	~LuaDataModel() { release(); }
	void release();
	bool valid() { return !!datamodel; }
};

class LuaTableDef : public Rml::VariableDefinition {
public:
	LuaTableDef(const struct LuaDataModel* model);
	virtual bool Get(void* ptr, Rml::DataVariant& variant);
	virtual bool Set(void* ptr, const Rml::DataVariant& variant);
	virtual int Size(void* ptr);
	virtual Rml::DataVariable Child(void* ptr, const Rml::DataAddressEntry& address);
protected:
	const struct LuaDataModel* model;
};

class LuaScalarDef final : public LuaTableDef {
public:
	LuaScalarDef(const struct LuaDataModel* model);
	virtual Rml::DataVariable Child(void* ptr, const Rml::DataAddressEntry& address);
};

LuaTableDef::LuaTableDef(const struct LuaDataModel *model)
	: VariableDefinition()
	, model(model)
{}

bool LuaTableDef::Get(void* ptr, Rml::DataVariant& variant) {
	lua_State *L = model->dataL;
	if (!L)
		return false;
	int id = (int)(intptr_t)ptr;
	lua_getvariant(L, id, &variant);
	return true;
}

bool LuaTableDef::Set(void* ptr, const Rml::DataVariant& variant) {
	int id = (int)(intptr_t)ptr;
	lua_State *L = model->dataL;
	if (!L)
		return false;
	lua_pushvariant(L, variant);
	lua_replace(L, id);
	return true;
}

static int
lLuaTableDefSize(lua_State* L) {
	lua_pushinteger(L, luaL_len(L, 1));
	return 1;
}

static int
lLuaTableDefChild(lua_State* L) {
	lua_gettable(L, 1);
	return 1;
}

int LuaTableDef::Size(void* ptr) {
	lua_State* L = model->dataL;
	if (!L)
		return 0;
	int id = (int)(intptr_t)ptr;
	if (lua_type(L, id) != LUA_TTABLE) {
		return 0;
	}
	if (!lua_checkstack(L, 4)) {
		return 0;
	}
	lua_pushcfunction(L, lLuaTableDefSize);
	lua_pushvalue(L, id);
	if (LUA_OK != lua_pcall(L, 1, 1, 0)) {
		lua_pop(L, 1);
		return 0;
	}
	int size = (int)lua_tointeger(L, -1);
	lua_pop(L, 1);
	return size;
}

Rml::DataVariable LuaTableDef::Child(void* ptr, const Rml::DataAddressEntry& address) {
	lua_State* L = model->dataL;
	if (!L)
		return Rml::DataVariable{};
	int id = (int)(intptr_t)ptr;
	if (lua_type(L, id) != LUA_TTABLE) {
		return Rml::DataVariable{};
	}
	if (!lua_checkstack(L, 4)) {
		return Rml::DataVariable{};
	}
	lua_pushcfunction(L, lLuaTableDefChild);
	lua_pushvalue(L, id);
	if (address.index == -1) {
		lua_pushlstring(L, address.name.data(), address.name.size());
	}
	else {
		lua_pushinteger(L, (lua_Integer)address.index + 1);
	}
	if (LUA_OK != lua_pcall(L, 2, 1, 0)) {
		lua_pop(L, 1);
		return Rml::DataVariable{};
	}
	return Rml::DataVariable(model->tableDef, (void*)(intptr_t)lua_gettop(L));
}

LuaScalarDef::LuaScalarDef(const struct LuaDataModel* model)
	: LuaTableDef(model)
{}

Rml::DataVariable LuaScalarDef::Child(void* ptr, const Rml::DataAddressEntry& address) {
	lua_State* L = model->dataL;
	if (!L)
		return Rml::DataVariable{};
	lua_settop(L, model->top);
	return LuaTableDef::Child(ptr, address);
}

static void
BindVariable(struct LuaDataModel* D, lua_State* L) {
	lua_State* dataL = D->dataL;
	if (!lua_checkstack(dataL, 4)) {
		luaL_error(L, "Memory Error");
	}
	int id = lua_gettop(dataL) + 1;
	D->top = id;
	// L top : key value
	lua_xmove(L, dataL, 1);	// move value to dataL with index(id)
	lua_pushvalue(L, -1);	// dup key
	lua_xmove(L, dataL, 1);
	lua_pushinteger(dataL, id);
	lua_rawset(dataL, 1);
	const char* key = lua_tostring(L, -1);
	if (lua_type(dataL, D->top) == LUA_TFUNCTION) {
		D->datamodel->BindEventCallback(key, [=](Rml::Event& event, const std::vector<Rml::DataVariant>& list) {
			luabind::invoke([&](lua_State* L){
				lua_pushvalue(dataL, id);
				lua_xmove(dataL, L, 1);
				get_lua_plugin()->pushevent(L, event);
				for (auto const& e : list) {
					lua_pushvariant(L, e);
				}
				lua_call(L, (int)list.size() + 1, 0);
			});
		});
	}
	else {
		D->datamodel->BindVariable(key,
			Rml::DataVariable(D->scalarDef, (void*)(intptr_t)id)
		);
	}
}

static int
getId(lua_State *L, lua_State *dataL) {
	lua_pushvalue(dataL, 1);
	lua_xmove(dataL, L, 1);
	lua_pushvalue(L, 2);
	if (lua_rawget(L, -2) != LUA_TNUMBER) {
		luaL_error(L, "DataModel has no key : %s", lua_tostring(L, 2));
	}
	int id = (int)lua_tointeger(L, -1);
	lua_pop(L, 2);
	return id;
}

int
lDataModelGet(lua_State *L) {
	struct LuaDataModel *D = (struct LuaDataModel *)lua_touserdata(L, 1);
	lua_State *dataL = D->dataL;
	if (dataL == NULL)
		luaL_error(L, "DataModel released");

	int id = getId(L, dataL);
	lua_pushvalue(dataL, id);
	lua_xmove(dataL, L, 1);
	return 1;
}

int
lDataModelSet(lua_State *L) {
	struct LuaDataModel *D = (struct LuaDataModel *)lua_touserdata(L, 1);
	lua_State *dataL = D->dataL;
	if (dataL == NULL)
		luaL_error(L, "DataModel released");
	lua_settop(dataL, D->top);

	lua_pushvalue(L, 2);
	lua_xmove(L, dataL, 1);
	if (lua_rawget(dataL, 1) == LUA_TNUMBER) {
		int id = (int)lua_tointeger(dataL, -1);
		lua_pop(dataL, 1);
		lua_xmove(L, dataL, 1);
		lua_replace(dataL, id);
		D->datamodel->DirtyVariable(lua_tostring(L, 2));
		return 0;
	}
	lua_pop(dataL, 1);
	BindVariable(D, L);
	return 0;
}

int
lDataModelDirty(lua_State* L) {
	struct LuaDataModel* D = (struct LuaDataModel*)lua_touserdata(L, 1);
	int n = lua_gettop(L);
	for (int i = 2; i <= n; ++i) {
		D->datamodel->DirtyVariable(luaL_checkstring(L, i));
	}
	return 0;
}

// We should release LuaDataModel manually
int
lDataModelRelease(lua_State *L) {
	struct LuaDataModel* D = (struct LuaDataModel*)lua_touserdata(L, 1);
	D->release();
	lua_pushnil(L);
	lua_setuservalue(L, -2);
	return 0;
}

int
lDataModelDelete(lua_State* L) {
	struct LuaDataModel* D = (struct LuaDataModel*)lua_touserdata(L, 1);
	D->~LuaDataModel();
	return 0;
}

LuaDataModel::LuaDataModel(Rml::Document* document)
	: datamodel(document->CreateDataModel())
	, scalarDef(new LuaScalarDef(this))
	, tableDef(new LuaTableDef(this))
	, dataL(nullptr)
	, top(0)
{ }

void LuaDataModel::release() {
	delete scalarDef;
	delete tableDef;
	dataL = nullptr;
	top = 0;
	scalarDef = nullptr;
	tableDef = nullptr;
}

int
lDataModelCreate(lua_State *L) {
	Rml::Document* document = (Rml::Document*)lua_touserdata(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE);

	struct LuaDataModel* D = (struct LuaDataModel*)lua_newuserdata(L, sizeof(*D));
	new (D) LuaDataModel(document);
	if (!D->valid()) {
		return luaL_error(L, "Can't create DataModel");
	}

	D->dataL = lua_newthread(L);
	D->top = 1;
	lua_newtable(D->dataL);
	lua_pushnil(L);
	while (lua_next(L, 2) != 0) {
		BindVariable(D, L);
	}
	lua_setuservalue(L, -2);
	return 1;
}
