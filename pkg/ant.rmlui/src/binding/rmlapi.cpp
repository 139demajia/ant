#include <lua.hpp>

#include <core/Core.h>
#include <core/Document.h>
#include <core/Element.h>
#include <core/Text.h>
#include <core/Texture.h>
#include <binding/luaplugin.h>
#include <binding/luabind.h>
#include <binding/render.h>
#include <binding/context.h>

#include <string.h>

struct RmlWrapper {
	RmlContext m_context;
	lua_plugin m_plugin;
	Renderer   m_renderer;
	RmlWrapper(lua_State* L, int idx)
		: m_context(L, idx)
		, m_plugin(L)
		, m_renderer(&m_context)
	{}
};

static RmlWrapper* g_wrapper = nullptr;

template <typename T>
T* lua_checkobject(lua_State* L, int idx) {
	luaL_checktype(L, idx, LUA_TLIGHTUSERDATA);
	return static_cast<T*>(lua_touserdata(L, idx));
}

static std::string
lua_checkstdstring(lua_State* L, int idx) {
	size_t sz = 0;
	const char* str = luaL_checklstring(L, idx, &sz);
	return std::string(str, sz);
}

static void
lua_pushstdstring(lua_State* L, const std::string& str) {
	lua_pushlstring(L, str.data(), str.size());
}

static int
lua_pushRmlNode(lua_State* L, const Rml::Node* node) {
	lua_pushlightuserdata(L, const_cast<Rml::Node*>(node));
	lua_pushinteger(L, (lua_Integer)node->GetType());
	return 2;
}

	
namespace {

static int
lDocumentCreate(lua_State* L) {
	Rml::Size dimensions(
		(float)luaL_checkinteger(L, 1),
		(float)luaL_checkinteger(L, 2)
	);
	Rml::Document* doc = new Rml::Document(dimensions);
	lua_pushlightuserdata(L, doc);
	return 1;
}

static int
lDocumentLoad(lua_State* L) {
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	std::string url = lua_checkstdstring(L, 2);
	bool ok = doc->Load(url);
	lua_pushboolean(L, ok);
	return 1;
}

static int
lDocumentDestroy(lua_State* L) {
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	delete doc;
	return 0;
}

static int
lDocumentUpdate(lua_State* L) {
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	float delta = (float)luaL_checknumber(L, 2);
	doc->Update(delta / 1000);
	return 0;
}

static int
lDocumentFlush(lua_State* L) {
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	doc->Flush();
	return 0;
}

static int
lDocumentSetDimensions(lua_State *L){
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	doc->SetDimensions(Rml::Size(
		(float)luaL_checkinteger(L, 2),
		(float)luaL_checkinteger(L, 3))
	);
	return 0;
}

static int
lDocumentElementFromPoint(lua_State *L){
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	Rml::Element* e = doc->ElementFromPoint(Rml::Point(
		(float)luaL_checknumber(L, 2),
		(float)luaL_checknumber(L, 3))
	);
	if (!e) {
		return 0;
	}
	lua_pushlightuserdata(L, e);
	return 1;
}

static int
lDocumentGetBody(lua_State* L) {
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	Rml::Element* e = doc->GetBody();
	lua_pushlightuserdata(L, e);
	return 1;
}

static int
lDocumentCreateElement(lua_State* L) {
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	Rml::Element* e = doc->CreateElement(lua_checkstdstring(L, 2));
	if (!e) {
		return 0;
	}
	e->NotifyCreated();
	lua_pushlightuserdata(L, e);
	return 1;
}

static int
lDocumentCreateTextNode(lua_State* L) {
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	Rml::Text* e = doc->CreateTextNode(lua_checkstdstring(L, 2));
	if (!e) {
		return 0;
	}
	lua_pushlightuserdata(L, e);
	return 1;
}

static int
lDocumentGetSourceURL(lua_State *L) {
	Rml::Document* doc = lua_checkobject<Rml::Document>(L, 1);
	const std::string &url = doc->GetSourceURL();
	lua_pushstdstring(L, url);
	return 1;
}

static int
lElementSetPseudoClass(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	const char* lst[] = { "hover", "active", NULL };
	Rml::PseudoClass pseudoClass = (Rml::PseudoClass)(1 + luaL_checkoption(L, 2, NULL, lst));
	e->SetPseudoClass(pseudoClass, lua_toboolean(L, 3));
	return 0;
}

static int
lElementGetScrollLeft(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_pushnumber(L, e->GetScrollLeft());
	return 1;
}

static int
lElementGetScrollTop(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_pushnumber(L, e->GetScrollTop());
	return 1;
}

static int
lElementSetScrollLeft(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->SetScrollLeft((float)luaL_checknumber(L, 2));
	return 0;
}

static int
lElementSetScrollTop(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->SetScrollTop((float)luaL_checknumber(L, 2));
	return 0;
}

static int
lElementSetScrollInsets(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	Rml::EdgeInsets<float> insets = {
		(float)luaL_checknumber(L, 2),
		(float)luaL_checknumber(L, 3),
		(float)luaL_checknumber(L, 4),
		(float)luaL_checknumber(L, 5),
	};
	e->SetScrollInsets(insets);
	return 0;
}

static int
lElementGetInnerHTML(lua_State *L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_pushstdstring(L, e->GetInnerHTML());
	return 1;
}

static int
lElementSetInnerHTML(lua_State *L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->SetInnerHTML(lua_checkstdstring(L, 2));
	return 0;
}

static int
lElementGetOuterHTML(lua_State *L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_pushstdstring(L, e->GetOuterHTML());
	return 1;
}

static int
lElementSetOuterHTML(lua_State *L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->SetOuterHTML(lua_checkstdstring(L, 2));
	return 0;
}

static int
lElementGetId(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_pushstdstring(L, e->GetId());
	return 1;
}

static int
lElementGetClassName(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_pushstdstring(L, e->GetClassName());
	return 1;
}

static int
lElementGetAttribute(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	const std::string* attr = e->GetAttribute(lua_checkstdstring(L, 2));
	if (!attr) {
		return 0;
	}
	lua_pushstdstring(L, *attr);
	return 1;
}

static int
lElementGetAttributes(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	const auto& attrs = e->GetAttributes();
	lua_createtable(L, 0, attrs.size());
	for (const auto& [k, v]: attrs) {
		lua_pushstdstring(L, k);
		lua_pushstdstring(L, v);
		lua_rawset(L, -3);
	}
	return 1;
}

static int
lElementGetBounds(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	const Rml::Rect& bounds = e->GetBounds();
	lua_pushnumber(L, bounds.origin.x);
	lua_pushnumber(L, bounds.origin.y);
	lua_pushnumber(L, bounds.size.w);
	lua_pushnumber(L, bounds.size.h);
	return 4;
}

static int
lElementGetTagName(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_pushstdstring(L, e->GetTagName());
	return 1;
}

static int
lElementAppendChild(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	Rml::Element* child = lua_checkobject<Rml::Element>(L, 2);
	auto index = (uint32_t)luaL_optinteger(L, 3, e->GetNumChildNodes());
	e->AppendChild(child, index);
	return 0;
}

static int
lElementInsertBefore(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	Rml::Node* child = lua_checkobject<Rml::Node>(L, 2);
	Rml::Node* adjacent = lua_checkobject<Rml::Node>(L, 3);
	e->InsertBefore(child, adjacent);
	return 0;
}

static int
lElementGetPreviousSibling(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_pushRmlNode(L, e->GetPreviousSibling());
	return 2;
}

static int
lElementRemoveChild(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	Rml::Element* child = lua_checkobject<Rml::Element>(L, 2);
	e->RemoveChild(child);
	return 0;
}

static int
lElementRemoveAllChildren(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->RemoveAllChildren();
	return 0;
}

static int
lElementGetChildren(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	if (lua_type(L, 2) != LUA_TNUMBER) {
		lua_pushinteger(L, e->GetNumChildNodes());
		return 1;
	}
	Rml::Node* child = e->GetChildNode((size_t)luaL_checkinteger(L, 2));
	if (child) {
		return lua_pushRmlNode(L, child);
	}
	return 0;
}

static int
lElementGetOwnerDocument(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	Rml::Document* doc = e->GetOwnerDocument();
	if (!doc) {
		return 0;
	}
	lua_pushlightuserdata(L, doc);
	return 1;
}

static int
lElementGetProperty(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	std::optional<std::string> prop = e->GetProperty(lua_checkstdstring(L, 2));
	if (!prop) {
		return 0;
	}
	lua_pushstdstring(L, *prop);
	return 1;
}

static int
lElementRemoveAttribute(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->RemoveAttribute(lua_checkstdstring(L, 2));
	return 0;
}

static int
lElementSetId(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->SetId(lua_checkstdstring(L, 2));
	return 0;
}

static int
lElementSetClassName(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->SetClassName(lua_checkstdstring(L, 2));
	return 0;
}

static int
lElementSetAttribute(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->SetAttribute(lua_checkstdstring(L, 2), lua_checkstdstring(L, 3));
	return 0;
}

static int
lElementSetProperty(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	std::string name = lua_checkstdstring(L, 2);
	if (lua_isnoneornil(L, 3)) {
		e->SetProperty(name);
	}
	else {
		std::string value = lua_checkstdstring(L, 3);
		e->SetProperty(name, value);
	}
	return 0;
}

static int
lElementSetVisible(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	bool visible = lua_toboolean(L, 2);
	e->SetVisible(visible);
	return 0;
}

static int
lElementProject(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	Rml::Point pt(
		(float)luaL_checknumber(L, 2),
		(float)luaL_checknumber(L, 3)
	);
	if (!e->Project(pt)) {
		return 0;
	}
	lua_pushnumber(L, pt.x);
	lua_pushnumber(L, pt.y);
	return 2;
}

static int
lElementDirtyImage(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	e->DirtyBackground();
	return 0;
}

static int
lElementDelete(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	delete e;
	return 0;
}

static int
lElementGetElementById(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	Rml::Element* element = e->GetElementById(lua_checkstdstring(L, 2));
	if (!element) {
		return 0;
	}
	lua_pushlightuserdata(L, element);
	return 1;
}

static int
lElementGetElementsByTagName(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_newtable(L);
	lua_Integer i = 0;
	e->GetElementsByTagName(lua_checkstdstring(L, 2), [&](Rml::Element* child) {
		lua_pushlightuserdata(L, child);
		lua_seti(L, -2, ++i);
	});
	return 1;
}

static int
lElementGetElementsByClassName(lua_State* L) {
	Rml::Element* e = lua_checkobject<Rml::Element>(L, 1);
	lua_newtable(L);
	lua_Integer i = 0;
	e->GetElementsByClassName(lua_checkstdstring(L, 2), [&](Rml::Element* child) {
		lua_pushlightuserdata(L, child);
		lua_seti(L, -2, ++i);
	});
	return 1;
}

static int
lNodeGetParent(lua_State* L) {
	Rml::Node* e = lua_checkobject<Rml::Node>(L, 1);
	Rml::Element* parent = e->GetParentNode();
	if (!parent) {
		return 0;
	}
	lua_pushlightuserdata(L, parent);
	return 1;
}

static int
lNodeClone(lua_State* L) {
	Rml::Node* e = lua_checkobject<Rml::Node>(L, 1);
	Rml::Node* r = e->Clone();
	if (!r) {
		return 0;
	}
	return lua_pushRmlNode(L, r);
}

static int
lTextGetText(lua_State* L) {
	Rml::Text* e = lua_checkobject<Rml::Text>(L, 1);
	lua_pushstdstring(L, e->GetText());
	return 1;
}

static int
lTextSetText(lua_State* L) {
	Rml::Text* e = lua_checkobject<Rml::Text>(L, 1);
	e->SetText(lua_checkstdstring(L, 2));
	return 0;
}

static int
lTextDelete(lua_State* L) {
	Rml::Text* e = lua_checkobject<Rml::Text>(L, 1);
	delete e;
	return 0;
}

static int
lRmlInitialise(lua_State* L) {
    if (g_wrapper) {
        return luaL_error(L, "RmlUi has been initialized.");
    }
    g_wrapper = new RmlWrapper(L, 1);
    if (!Rml::Initialise()){
        return luaL_error(L, "Failed to Initialise RmlUi.");
    }
    return 0;
}

static int
lRmlShutdown(lua_State* L) {
    Rml::Shutdown();
    if (g_wrapper) {
        delete g_wrapper;
        g_wrapper = nullptr;
    }
    return 0;
}

static int
lRenderBegin(lua_State* L) {
	Rml::GetRenderInterface()->Begin();
	return 0;
}

static int
lRenderFrame(lua_State* L) {
	Rml::GetRenderInterface()->End();
    return 0;
}

static int
lRenderSetTexture(lua_State* L) {
	Rml::TextureData data;
	if (lua_gettop(L) >= 4) {
		data.handle = (Rml::TextureId)luaL_checkinteger(L, 2);
		data.dimensions.w = (float)luaL_checkinteger(L, 3);
		data.dimensions.h = (float)luaL_checkinteger(L, 4);
	}
	Rml::Texture::Set(lua_checkstdstring(L, 1), std::move(data));
    return 0;
}

}

lua_plugin* get_lua_plugin() {
    return &g_wrapper->m_plugin;
}

extern "C"
#if defined(_WIN32)
__declspec(dllexport)
#endif
int
luaopen_rmlui(lua_State* L) {
	luaL_checkversion(L);
	luabind::init(L);
	luaL_Reg l[] = {
		{ "DocumentCreate", lDocumentCreate },
		{ "DocumentLoad", lDocumentLoad },
		{ "DocumentDestroy", lDocumentDestroy },
		{ "DocumentUpdate", lDocumentUpdate },
		{ "DocumentFlush", lDocumentFlush },
		{ "DocumentSetDimensions", lDocumentSetDimensions},
		{ "DocumentElementFromPoint", lDocumentElementFromPoint },
		{ "DocumentGetSourceURL", lDocumentGetSourceURL },
		{ "DocumentGetBody", lDocumentGetBody },
		{ "DocumentCreateElement", lDocumentCreateElement },
		{ "DocumentCreateTextNode", lDocumentCreateTextNode },
		{ "ElementGetId", lElementGetId },
		{ "ElementGetClassName", lElementGetClassName },
		{ "ElementGetAttribute", lElementGetAttribute },
		{ "ElementGetAttributes", lElementGetAttributes },
		{ "ElementGetBounds", lElementGetBounds },
		{ "ElementGetTagName", lElementGetTagName },
		{ "ElementGetChildren", lElementGetChildren },
		{ "ElementGetOwnerDocument", lElementGetOwnerDocument },
		{ "ElementGetProperty", lElementGetProperty },
		{ "ElementRemoveAttribute", lElementRemoveAttribute },
		{ "ElementSetId", lElementSetId },
		{ "ElementSetClassName", lElementSetClassName },
		{ "ElementSetAttribute", lElementSetAttribute },
		{ "ElementSetProperty", lElementSetProperty },
		{ "ElementSetVisible", lElementSetVisible },
		{ "ElementSetPseudoClass", lElementSetPseudoClass },
		{ "ElementGetScrollLeft", lElementGetScrollLeft },
		{ "ElementGetScrollTop", lElementGetScrollTop },
		{ "ElementSetScrollLeft", lElementSetScrollLeft },
		{ "ElementSetScrollTop", lElementSetScrollTop },
		{ "ElementSetScrollInsets", lElementSetScrollInsets },
		{ "ElementGetInnerHTML", lElementGetInnerHTML },
		{ "ElementSetInnerHTML", lElementSetInnerHTML },
		{ "ElementGetOuterHTML", lElementGetOuterHTML },
		{ "ElementSetOuterHTML", lElementSetOuterHTML },
		{ "ElementAppendChild", lElementAppendChild },
		{ "ElementInsertBefore", lElementInsertBefore },
		{ "ElementGetPreviousSibling", lElementGetPreviousSibling },
		{ "ElementRemoveChild", lElementRemoveChild },
		{ "ElementRemoveAllChildren", lElementRemoveAllChildren},
		{ "ElementGetElementById", lElementGetElementById },
		{ "ElementGetElementsByTagName", lElementGetElementsByTagName },
		{ "ElementGetElementsByClassName", lElementGetElementsByClassName },
		{ "ElementDelete", lElementDelete },
		{ "ElementProject", lElementProject },
		{ "ElementDirtyImage", lElementDirtyImage },
		{ "NodeGetParent", lNodeGetParent },
		{ "NodeClone", lNodeClone },
		{ "TextGetText", lTextGetText },
		{ "TextSetText", lTextSetText },
		{ "TextDelete", lTextDelete },
		{ "RenderBegin", lRenderBegin },
		{ "RenderFrame", lRenderFrame },
		{ "RenderSetTexture", lRenderSetTexture },
		{ "RmlInitialise", lRmlInitialise },
		{ "RmlShutdown", lRmlShutdown },
		{ NULL, NULL },
	};
	luaL_newlib(L, l);
	return 1;
}
