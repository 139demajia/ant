#define LUA_LIB
#define GLM_ENABLE_EXPERIMENTAL

extern "C" {
	#include "linalg.h"	
	#include "refstack.h"
	#include "fastmath.h"
	#include "math3d.h"
}

#include "util.h"

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/quaternion.hpp>
#include <glm/gtx/quaternion.hpp>
#include <glm/ext/scalar_relational.hpp>
#include <glm/ext/vector_relational.hpp>

//#include <glm/vector_relational.hpp>

#include <glm/gtx/euler_angles.hpp>


extern "C" {
	#include <lua.h>
	#include <lauxlib.h>
}

#include <inttypes.h>
#include <string.h>
#include <assert.h>
#include <math.h>
#include <string.h>
#include <stdbool.h>

#include <vector>

//#define __CLOCKWISE 1

#define MAT_PERSPECTIVE 0
#define MAT_ORTHO 1

static bool g_default_homogeneous_depth = false;

bool default_homogeneous_depth(){
	return g_default_homogeneous_depth;
}

/*
static inline float
get_angle(lua_State *L, int index) {
	int type = lua_type(L, index);
	switch (type) {
	case LUA_TNUMBER:
		return lua_tonumber(L, index);
	case LUA_TSTRING: {
		float degree = lua_tonumber(L, index);	// all degree should be string like "30"
		return glm::radians(degree);
	}
	case LUA_TNIL:
		return 0;
	default:
		return luaL_error(L, "Invalid angle type %s", lua_typename(L, lua_type(L, index)));
	}
}
*/
static const char *
get_typename(uint32_t t) {
	static const char * type_names[] = {
		"matrix",
		"vector4",
		"vector3",
		"quaternion",
		"number",
	};
	if (t < 0 || t >= sizeof(type_names)/sizeof(type_names[0]))
		return "unknown";
	return type_names[t];
}

static inline int64_t
pop(lua_State *L, struct lastack *LS) {
	int64_t v = lastack_pop(LS);
	if (v == 0)
		luaL_error(L, "pop empty stack");
	return v;
}

static int
delLS(lua_State *L) {
	struct boxstack *bp = (struct boxstack *)lua_touserdata(L, 1);
	if (bp->LS) {
		lastack_delete(bp->LS);
		bp->LS = NULL;
	}
	return 0;
}

static void
value_tostring(lua_State *L, const char * prefix, const float *r, int type) {
	char buffer[512] = { 0 };
	switch (type) {
	case LINEAR_TYPE_MAT:		
		sprintf(buffer, "%sMAT (%.2f,%.2f,%.2f,%.2f : %.2f,%.2f,%.2f,%.2f : %.2f,%.2f,%.2f,%.2f : %.2f,%.2f,%.2f,%.2f)",
			prefix,
			r[0],r[1],r[2],r[3],
			r[4],r[5],r[6],r[7],
			r[8],r[9],r[10],r[11],
			r[12],r[13],r[14],r[15]
		);		
		break;
	case LINEAR_TYPE_VEC4:
		sprintf(buffer, "%sVEC4 (%.2f,%.2f,%.2f,%.2f)", prefix, r[0],r[1],r[2],r[3]);		
		break;	
	case LINEAR_TYPE_QUAT:
		sprintf(buffer, "%sQUAT (%.2f,%.2f,%.2f,%.2f)", prefix, r[0],r[1],r[2],r[3]);
		break;
	case LINEAR_TYPE_NUM:
		sprintf(buffer, "%sNUMBER (%.2f)", prefix, r[0]);
		break;
	case LINEAR_TYPE_EULER:
		sprintf(buffer, "%sEULER (yaw(y) = %.2f, pitch(x) = %.2f, roll(z) = %.2f)", prefix, r[0], r[1], r[2]);
		break;
	default:
		sprintf(buffer, "%sUNKNOWN", prefix);
		break;
	}

	lua_pushstring(L, buffer);
}

static int
lreftostring(lua_State *L) {
	struct refobject * ref = (struct refobject *)lua_touserdata(L, 1);
	int sz;
	const float * v = lastack_value(ref->LS, ref->id, &sz);
	if (v == NULL) {
		char tmp[64];
		return luaL_error(L, "Invalid ref object [%s]", lastack_idstring(ref->id, tmp));
	}
	value_tostring(L, "&", v, sz);
	return 1;
}

static inline const char*
get_linear_type_name(LinearType lt) {
	const char * names[] = {
		"mat", "v4", "num", "quat", "euler", "",
	};

	assert((sizeof(names) / sizeof(names[0])) > size_t(lt));
	return names[lt];
}

static inline void
push_obj_to_lua_table(lua_State *L, struct lastack *LS, int64_t id){
	int type;
	const float * val = lastack_value(LS, id, &type);
	lua_newtable(L);

#define TO_LUA_STACK(_VV, _LUA_STACK_IDX) lua_pushnumber(L, _VV);	lua_seti(L, -2, _LUA_STACK_IDX)
	switch (type)
	{
	case LINEAR_TYPE_MAT:
		for (int i = 0; i < 16; ++i) {
			TO_LUA_STACK(val[i], i + 1);
		}
		break;
	case LINEAR_TYPE_QUAT:
	case LINEAR_TYPE_VEC4:
		TO_LUA_STACK(val[3], 3 + 1);	
	case LINEAR_TYPE_EULER:
		for (int i = 0; i < 3; ++i) {
			TO_LUA_STACK(val[i], i + 1);
		}
		break;
	case LINEAR_TYPE_NUM:
		TO_LUA_STACK(val[0], 0 + 1);
		break;
	default:
		break;
	}
#undef TO_LUA_STACK

	// push type to table	
	lua_pushstring(L, get_linear_type_name(LinearType(type)));	
	lua_setfield(L, -2, "type");
}

static inline int
unpack_obj(lua_State *L, struct lastack *LS, int64_t id) {
	int type;
	int i;
	const float * val = lastack_value(LS, id, &type);
	int n;
	switch (type) {
	case LINEAR_TYPE_MAT:
		n = 16;
		break;
	case LINEAR_TYPE_QUAT:
	case LINEAR_TYPE_VEC4:
		n = 4;
		break;
	case LINEAR_TYPE_EULER:
		n = 3;
		break;
	case LINEAR_TYPE_NUM:
		n = 1;
		break;
	default:
		n = 0;
		break;
	}
	for (i=0;i<n;i++) {
		lua_pushnumber(L, val[i]);
	}
	return n;
}

static inline int
is_ref_obj(lua_State *L){
	size_t si = lua_rawlen(L, 1);
	return si == sizeof(struct refobject);
}

static int
ref_to_value(lua_State *L) {
	if (!is_ref_obj(L)){
		luaL_error(L, "arg 1 is not a math3d refobject!");
	}

	struct refobject *ref = (struct refobject *)lua_touserdata(L, 1);
	push_obj_to_lua_table(L, ref->LS, ref->id);

	return 1;
}

static int
ref_unpack_value(lua_State *L) {
	if (!is_ref_obj(L)){
		luaL_error(L, "arg 1 is not a math3d refobject!");
	}

	struct refobject *ref = (struct refobject *)lua_touserdata(L, 1);

	return unpack_obj(L, ref->LS, ref->id);
}

static int
ref_clone_value(lua_State *L) {
	if (!is_ref_obj(L)){
		luaL_error(L, "arg 1 is not a math3d refobject!");
	}

	struct refobject *ref = (struct refobject *)lua_touserdata(L, 1);
	lua_pushinteger(L, ref->id);

	return 1;
}

static inline void
release_ref(lua_State *L, struct refobject *ref) {
	if (ref->LS) {
		ref->id = lastack_unmark(ref->LS, ref->id);
	}
}

static inline int64_t
get_id(lua_State *L, int index) {
	int64_t v;
	if (sizeof(lua_Integer) >= sizeof(int64_t)) {
		v = lua_tointeger(L, index);
	} else {
		v = (int64_t)lua_tonumber(L, index);
	}
	return v;
}

static inline int64_t
get_ref_id(lua_State *L, struct lastack *LS, int index) {
	struct refobject * ref = (struct refobject *)lua_touserdata(L, index);
	if (lua_rawlen(L, index) != sizeof(*ref)) {
		luaL_error(L, "The userdata is not a ref object");
	}
	if (ref->LS == NULL) {
		ref->LS = LS;
	} else if (ref->LS != LS) {
		luaL_error(L, "ref object not belongs this stack");
	}

	return ref->id;
}

static inline int64_t
get_id_by_type(lua_State *L, struct lastack *LS, int lType, int index) {
	return lType == LUA_TNUMBER ? get_id(L, index) : get_ref_id(L, LS, index);
}

int64_t
get_stack_id(lua_State *L, struct lastack *LS, int index) {
	const int type = lua_type(L, index);
	return get_id_by_type(L, LS, type, index);
}

void
assign_ref(lua_State *L, struct refobject * ref, int64_t rid) {
	int64_t markid = lastack_mark(ref->LS, rid);
	if (markid == 0) {
		luaL_error(L, "Mark invalid object id");
		return;
	}
	lastack_unmark(ref->LS, ref->id);
	ref->id = markid;
}

static inline glm::vec3
extract_scale(lua_State *L, struct lastack *LS, int index){	
	glm::vec3 scale(1, 1, 1);
	int stype = lua_type(L, index);
	if (stype == LUA_TNUMBER || stype == LUA_TUSERDATA) {
		int64_t id = get_id_by_type(L, LS, stype, index);
		int type;
		const float *value = lastack_value(LS, id, &type);
		switch (type)
		{
		case LINEAR_TYPE_VEC4:
			scale = *(glm::vec3*)value;
			break;
		default:
			luaL_error(L, "linear type should be vec3/vec4, type is : %d", type);
			break;
		}
	} else if (stype == LUA_TTABLE) {
		size_t len = lua_rawlen(L, index);		
		if (len == 1) {
			float s = get_table_item(L, index, 1);
			scale[0] = scale[1] = scale[2] = s;
		} else if (len == 3||len == 4) {
			get_table_value(L, index, 3, scale);			
		} else {
			luaL_error(L, "using table for s element, format must be s = {1}/{1, 2, 3}, give number : %d", len);
		}		
	} else if (stype != LUA_TNIL) {
		luaL_error(L, "Invalid scale type %s", lua_typename(L, stype));
	}
	return scale;
}

static inline glm::vec3
extract_translate(lua_State *L, struct lastack *LS, int index){
	glm::vec3 translate(0, 0, 0);
	const int ttype = lua_type(L, index);
	if (ttype == LUA_TNUMBER || ttype == LUA_TUSERDATA) {
		int64_t id = get_id_by_type(L, LS, ttype, index);
		int type;
		const float *value = lastack_value(LS, id, &type);
		if (type != LINEAR_TYPE_VEC4)
			luaL_error(L, "t field should provide vec4, provide type is : %d", type);

		if (value == NULL)
			luaL_error(L, "invalid id : %ld, get NULL value", id);
		
		translate = *((glm::vec3*)value);
	} else if (ttype == LUA_TTABLE) {
		size_t len = lua_rawlen(L, index);
		if (len < 3)
			luaL_error(L, "t field should : t={1, 2, 3}, only accept 3 value, %d is give", len);

		get_table_value(L, index, 3, translate);
	} else if (ttype != LUA_TNIL) {
		luaL_error(L, "Invalid translate type %s", lua_typename(L, ttype));
	}
	return translate;
}

static inline glm::mat4x4
extract_rotation_mat(lua_State *L, struct lastack *LS, int index){
	glm::mat4x4 m;
	const int rtype = lua_type(L, index);
	if (rtype == LUA_TNUMBER || rtype == LUA_TUSERDATA) {
		int64_t id = get_id_by_type(L, LS, rtype, index);
		int type;
		const float *value = lastack_value(LS, id, &type);

		if (type != LINEAR_TYPE_VEC4 && type != LINEAR_TYPE_EULER)
			luaL_error(L, "ref object need should be vec4/euler!, type is : %d", type);

		m = glm::mat4x4(glm::quat(*(const glm::vec3*)value));
	} else if (rtype == LUA_TTABLE) {
		const size_t len = lua_rawlen(L, index);

		if (len == 3) {
			//the table is define as : rotate x-axis(pitch), rotate y-axis(yaw), rotate z-axis(roll)
			glm::vec3 e;
			for (int ii = 0; ii < 3; ++ii)
				e[ii] = get_table_item(L, index, ii + 1);

			// be careful here, glm::quat(euler_angles) result is different from eulerAngleXYZ()
			// keep the same order with glm::quat
			m = glm::mat4x4(glm::quat(e));
		} else if (len == 4) {
			glm::quat q;
			get_table_value(L, index, 4, q);
			m = glm::mat4x4(q);
		} else {
			luaL_error(L, "r field should : \
							1. with 3 element(euler angle): r={1, 2, 3}, only accept 3 value;\n\
							2. with 4 element(quaternion): r={0, 0, 0, 1};\n\
							%d is give", len);
		}
	} else {
		m = glm::mat4x4(1.f);
		if (rtype != LUA_TNIL)
			luaL_error(L, "Invalid rotation type %s", lua_typename(L, rtype));
	}

	return m;
}


static void inline
make_srt(struct lastack*LS, const glm::vec3 &scale, const glm::mat4x4 &rotmat, const glm::vec3 &translate) {
	glm::mat4x4 srt(1);
	#ifdef __CLOCKWISE
	srt[0][0] = -scale[0];
	#else 
	srt[0][0] = scale[0];
	#endif  
	srt[1][1] = scale[1];
	srt[2][2] = scale[2];

	srt = rotmat * srt;
	srt[3] = glm::vec4(translate, 1);
	lastack_pushmatrix(LS, &srt[0][0]);
}

static void inline 
push_srt_from_table(lua_State *L, struct lastack *LS, int index) {
	lua_getfield(L, index, "s");
	const glm::vec3 scale = extract_scale(L, LS, -1);
	lua_pop(L, 1);
	
	lua_getfield(L, index, "r");
	const glm::mat4x4 rotMat = extract_rotation_mat(L, LS, -1);
	lua_pop(L, 1);

	lua_getfield(L, index, "t");
	const glm::vec3 translate = extract_translate(L, LS, -1);	
	lua_pop(L, 1);
	 
	make_srt(LS, scale, rotMat, translate);
}

static int
get_mat_type(lua_State *L, int index) {
	const int ret_type = lua_getfield(L, index, "ortho");
	
	int mat_type = MAT_PERSPECTIVE;
	if (ret_type != LUA_TNIL && ret_type != LUA_TNONE) {
		if (ret_type != LUA_TBOOLEAN) {
			luaL_error(L, "ortho field must be boolean type, get %d", ret_type);
		}

		mat_type = lua_toboolean(L, -1) != 0 ? MAT_ORTHO : MAT_PERSPECTIVE;
	}
	lua_pop(L, 1);
	return mat_type;
}

glm::mat4x4
create_proj_mat(lua_State *L, struct lastack *LS, int index) {
	float left, right, top, bottom;
	lua_getfield(L, index, "n");
	float near = luaL_optnumber(L, -1, 0.1f);
	lua_pop(L, 1);
	lua_getfield(L, index, "f");
	float far = luaL_optnumber(L, -1, 100.0f);
	lua_pop(L, 1);

	int mattype = MAT_PERSPECTIVE;
	if (lua_getfield(L, index, "fov") == LUA_TNUMBER) {
		float fov = lua_tonumber(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, index, "aspect");
		float aspect = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		float ymax = near * tanf(fov * (M_PI / 360));
		float xmax = ymax * aspect;
		left = -xmax;
		right = xmax;
		bottom = -ymax;
		top = ymax;
	} else {
		mattype = get_mat_type(L, index);
		lua_getfield(L, index, "l");
		left = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, index, "r");
		right = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, index, "b");
		bottom = luaL_checknumber(L, -1);
		lua_pop(L, 1);
		lua_getfield(L, index, "t");
		top = luaL_checknumber(L, -1);
		lua_pop(L, 1);
	}

	if (mattype == MAT_PERSPECTIVE) {
		return g_default_homogeneous_depth ?
			glm::frustumLH_NO(left, right, bottom, top, near, far) :
			glm::frustumLH_ZO(left, right, bottom, top, near, far);
	} else {
		return g_default_homogeneous_depth ?
			glm::orthoLH_NO(left, right, bottom, top, near, far) :
			glm::orthoLH_ZO(left, right, bottom, top, near, far);
	}
}

static inline void
push_proj_mat(lua_State *L, struct lastack *LS, int index) {
	auto m = create_proj_mat(L, LS, index);
	lastack_pushmatrix(LS, &m[0][0]);
}

static inline const char*
get_field(lua_State *L, int index, const char* name) {
	const char* field = NULL;
	if (lua_getfield(L, index, name) == LUA_TSTRING) {
		field = lua_tostring(L, -1);
		lua_pop(L, 1);
	}

	return field;
}

static inline const char * 
get_type_field(lua_State *L, int index) {
	return get_field(L, index, "type");
}

static inline void
push_quat_with_axis_radian(lua_State* L, struct lastack *LS, int index) {
	// get axis
	lua_getfield(L, index, "axis");

	glm::vec3 axis;
	int axis_type = lua_type(L, -1);
	switch (axis_type) {
	case LUA_TTABLE: {
		get_table_value(L, -1, 3, axis);		
		break;
	}
	case LUA_TNUMBER: {
		int64_t stackid = get_id(L, -1);
		int t;
		const float *address = lastack_value(LS, stackid, &t);
		memcpy(&axis.x, address, sizeof(float) * 3);
		break;
	}
	case LUA_TSTRING: {
		const char* t = lua_tostring(L, -1);
		axis[0] = 0; axis[1] = 0; axis[2] = 0;
		if (strcmp(t, "x") == 0 || strcmp(t, "X") == 0)
			axis[0] = 1;
		else if (strcmp(t, "y") == 0 || strcmp(t, "Y") == 0)
			axis[1] = 1;
		else if (strcmp(t, "z") == 0 || strcmp(t, "X") == 0)
			axis[2] = 1;
		else
			luaL_error(L, "not support this string type : %s", t);
		break;
	}
	default:
		luaL_error(L, "quaternion axis radian init, only support table and number, type is : %d", axis_type);
	}

	lua_pop(L, 1);

	// get radian
	lua_getfield(L, index, "radian");
	int radian_type = lua_type(L, -1);
	if (radian_type != LUA_TTABLE) {
		luaL_error(L, "radian should define as radian = {xx}");
	}
	const float radian = get_table_item(L, -1, 1);
	lua_pop(L, 1);

	glm::quat q = glm::angleAxis(radian, axis);
	lastack_pushquat(LS, &q.x);
}

static inline void
push_quat_with_euler(lua_State* L, struct lastack *LS, int index) {
	lua_getfield(L, index, "pyr");
	glm::vec3 e;
	int luaType = lua_type(L, -1);
	switch (luaType)
	{
	case LUA_TTABLE: 
		get_table_value(L, -1, 3, e);		
		break;
	case LUA_TNUMBER: {
		int64_t stackid = get_id(L, -1);
		int type;
		const float *value = lastack_value(LS, stackid, &type);
		if (type == LINEAR_TYPE_VEC4 || type == LINEAR_TYPE_EULER) {
			memcpy(&e, value, sizeof(float) * 3);
		} else {
			luaL_error(L, "using vec3/vec4 to define roll(z) pitch(x) yaw(y), type define is : %d", type);
		}

		break;
	}
	default:
		luaL_error(L, "create quaternion from euler failed, unknown type, %d", luaType);
	}

	lua_pop(L, 1);

	glm::quat q(e);
	lastack_pushquat(LS, &(q.x));
}

static inline void 
push_quat(lua_State* L, struct lastack *LS, int index) {
	lua_getfield(L, index, "pyr");	// pyr -> pitch, yaw, roll
	int curType = lua_type(L, -1);
	lua_pop(L, 1);

	if (curType == LUA_TTABLE || curType == LUA_TNUMBER) {
		push_quat_with_euler(L, LS, index);
	} else {
		push_quat_with_axis_radian(L, LS, index);
	}
}

static inline void
push_euler(lua_State *L, struct lastack *LS, int index) {
	glm::vec3 e;
	const uint32_t n = (uint32_t)lua_rawlen(L, index);
	
	if (n == 3) {
		get_table_value(L, index, 3, e);		
	} else {
		const char* names[] = { "pitch", "yaw", "roll" };		
		for (uint32_t i = 0; i < (sizeof(names) / sizeof(names[0])); ++i) {
			lua_getfield(L, index, names[i]);
			if (lua_type(L, -1) != LUA_TNIL) {
				e[i] = lua_tonumber(L, -1);
			}
			lua_pop(L, 1);
		}
	}	
	lastack_pusheuler(LS, &e.x);
}

static void
push_value(lua_State *L, struct lastack *LS, int index) {
	int n = (int)lua_rawlen(L, index);	
	float v[16];
	if (n > 16) {
		luaL_error(L, "Invalid value %d", n);
	}
	if (n == 0) {
		const char * type = get_type_field(L, index);
		if (type == NULL || strcmp(type, "srt") == 0) {
			push_srt_from_table(L, LS, index);		
		} else if (strcmp(type, "mat") == 0 || strcmp(type, "m") == 0) {
			push_proj_mat(L, LS, index);
		} else if (strcmp(type, "quat") == 0 || strcmp(type, "q") == 0) {
			push_quat(L, LS, index);
		} else if (strcmp(type, "euler") == 0 || strcmp(type, "e") == 0) {
			push_euler(L, LS, index);
		} else {
			luaL_error(L, "Invalid matrix type %s", type);
		}
		return;
	}
	luaL_checkstack(L, n, NULL);

	get_table_value(L, index, n, v);
	
	switch (n) {	
	case 1:
		lastack_pushnumber(LS, v[0]);
		break;
	case 3: {
		const char* type = get_type_field(L, index);
		if (type != NULL)
			push_euler(L, LS, index);
		else {
			v[3] = 0;
			lastack_pushvec4(LS, v);
		}			
		break;
	}
	case 4:	{
		const char* type = get_type_field(L, index);
		if (type != NULL && (strcmp(type, "quat") == 0 || strcmp(type, "q") == 0))
			lastack_pushquat(LS, v);
		else
			lastack_pushvec4(LS, v);
		break;
	}		
	case 16:
		lastack_pushmatrix(LS, v);
		break;
	default:
		luaL_error(L, "Invalid value %d", n);
	}
}

static inline void
pushid(lua_State *L, int64_t v) {
	if (sizeof(lua_Integer) >= sizeof(int64_t)) {
		lua_pushinteger(L, v);
	} else {
		lua_pushnumber(L, (lua_Number)v);
	}
}

static inline void
pop2_values(lua_State *L, struct lastack *LS, const float *val[2], int types[2]) {
	int64_t v1 = pop(L, LS);
	int64_t v2 = pop(L, LS);

	val[1] = lastack_value(LS, v1, types);
	val[0] = lastack_value(LS, v2, types + 1);
	if (types[0] != types[1]) {
		if (!lastack_is_vec_type(types[0]) && !lastack_is_vec_type(types[1]))
			luaL_error(L, "pop2_values : type mismatch, type0 = %d, type1 = %d", types[0], types[1]);
	}		
}

static void
add_2values(lua_State *L, struct lastack *LS) {
	const float *val[2];
	int types[2];
	pop2_values(L, LS, val, types);
	float ret[4];
	switch (types[0]) {
	case LINEAR_TYPE_NUM:
		ret[0] = val[0][0] + val[1][0];
		lastack_pushnumber(LS, ret[0]);
		break;
	case LINEAR_TYPE_VEC4:
		ret[0] = val[0][0] + val[1][0];
		ret[1] = val[0][1] + val[1][1];
		ret[2] = val[0][2] + val[1][2];
		ret[3] = val[0][3];		
		lastack_pushvec4(LS, ret);
		break;
	case LINEAR_TYPE_EULER:
		if (types[1] != LINEAR_TYPE_EULER)
			luaL_error(L, "Invalid type for euler to add, only support euler + euler, type0 = %d, type1 = %d", types[0], types[1]);
		ret[0] = val[0][0] + val[1][0];
		ret[1] = val[0][1] + val[1][1];
		ret[2] = val[0][2] + val[1][2];
		lastack_pusheuler(LS, ret);
		break;
	default:
		luaL_error(L, "Invalid type %d to add", types[0]);
	}
}

static void
sub_2values(lua_State *L, struct lastack *LS) {
	const float *val[2];
	int types[2];
	pop2_values(L, LS, val, types);
	float ret[4];
	switch (types[0]) {
	case LINEAR_TYPE_NUM:
		ret[0] = val[0][0] - val[1][0];
		lastack_pushnumber(LS, ret[0]);
		break;
	case LINEAR_TYPE_VEC4:
		ret[0] = val[0][0] - val[1][0];
		ret[1] = val[0][1] - val[1][1];
		ret[2] = val[0][2] - val[1][2];		
		ret[3] = 0.f; // must be 0, dir - point is no meaning
		lastack_pushvec4(LS, ret);
		break;
	case LINEAR_TYPE_EULER:
		ret[0] = val[0][0] - val[1][0];
		ret[1] = val[0][1] - val[1][1];
		ret[2] = val[0][2] - val[1][2];
		lastack_pusheuler(LS, ret);
		break;

	default:
		luaL_error(L, "Invalid type %d to add", types[0]);
	}
}

static const float *
pop_value(lua_State *L, struct lastack *LS, int *type) {
	int64_t v = pop(L, LS);
	int t = 0;
	const float * r = lastack_value(LS, v, &t);
	if (type)
		*type = t;
	return r;
}

static void
normalize(lua_State *L, struct lastack *LS) {
	int t;
	const float *v = pop_value(L, LS, &t);
	switch(t){
	case LINEAR_TYPE_VEC4:{
			glm::vec4 r(glm::normalize(*(glm::vec3*)(v)), v[3]);
			lastack_pushvec4(LS, &r.x);
		}		
		break;
	case LINEAR_TYPE_QUAT:{
			glm::quat q = glm::normalize(*(glm::quat*)(v));
			lastack_pushquat(LS, &q.x);
		}
		break;
	default:
		luaL_error(L, "normalize need quat or vec4");
		break;
	}
}

#define BINTYPE(v1, v2) (((v1) << LINEAR_TYPE_BITS_NUM) + (v2))

static void
mul_2values(lua_State *L, struct lastack *LS) {
	int64_t v1 = pop(L, LS);
	int64_t v0 = pop(L, LS);
	int t0,t1;
	const float * val1 = lastack_value(LS, v1, &t1);
	const float * val0 = lastack_value(LS, v0, &t0);
	int type = BINTYPE(t0,t1);
	switch (type) {
	case BINTYPE(LINEAR_TYPE_MAT,LINEAR_TYPE_MAT): {
		glm::mat4x4 m = *((const glm::mat4x4*)val0) * *((const glm::mat4x4*)val1);
		lastack_pushmatrix(LS, &m[0][0]);
		break;
	}
	case BINTYPE(LINEAR_TYPE_MAT, LINEAR_TYPE_VEC4): {
		glm::vec4 r = *((const glm::mat4x4*)val0) * *((const glm::vec4*)val1);
		lastack_pushvec4(LS, &r.x);
		break;
	}
	case BINTYPE(LINEAR_TYPE_VEC4, LINEAR_TYPE_MAT): {
		glm::vec4 r = *((const glm::vec4*)val0) * *((const glm::mat4x4*)val1);
		lastack_pushvec4(LS, &r.x);
		break;
	}
	case BINTYPE(LINEAR_TYPE_VEC4, LINEAR_TYPE_NUM):
	case BINTYPE(LINEAR_TYPE_NUM, LINEAR_TYPE_VEC4): {
		const glm::vec4 *v4 = (const glm::vec4 *)(type == BINTYPE(LINEAR_TYPE_VEC4, LINEAR_TYPE_NUM) ? val0 : val1);
		const float *vv = type == BINTYPE(LINEAR_TYPE_VEC4, LINEAR_TYPE_NUM) ? val1 : val0;

		glm::vec4 r = *v4 * *vv;		
		lastack_pushvec4(LS, &r.x);
		break;
	}
	case BINTYPE(LINEAR_TYPE_QUAT, LINEAR_TYPE_QUAT): {
		glm::quat r = *((const glm::quat *)val0) * *((const glm::quat*)val1);
		lastack_pushquat(LS, &r.x);
		break;
	}
	case BINTYPE(LINEAR_TYPE_QUAT, LINEAR_TYPE_VEC4):
	case BINTYPE(LINEAR_TYPE_VEC4, LINEAR_TYPE_QUAT): {
		const glm::quat *q = (const glm::quat*)(type == BINTYPE(LINEAR_TYPE_QUAT, LINEAR_TYPE_VEC4) ? val0 : val1);
		const glm::vec4 *v = (const glm::vec4 *)(type == BINTYPE(LINEAR_TYPE_QUAT, LINEAR_TYPE_VEC4) ? val1 : val0);

		glm::vec4 r = glm::rotate(*q, *v);
		lastack_pushvec4(LS, &r.x);
		break;
	}
	case BINTYPE(LINEAR_TYPE_EULER, LINEAR_TYPE_VEC4):
	case BINTYPE(LINEAR_TYPE_VEC4, LINEAR_TYPE_EULER): {		
		const glm::vec3 *e = (const glm::vec3*)(type == BINTYPE(LINEAR_TYPE_EULER, LINEAR_TYPE_VEC4) ? val0 : val1);
		const glm::vec4 *v = (const glm::vec4 *)(type == BINTYPE(LINEAR_TYPE_EULER, LINEAR_TYPE_VEC4) ? val1 : val0);

		glm::vec4 r = glm::rotate(glm::quat(*e), *v);
		lastack_pushvec4(LS, &r.x);
		break;
	}

	default:
		luaL_error(L, "Need support type %s * type %s", get_typename(t0),get_typename(t1));
	}
}

static void mulH_2values(lua_State *L, struct lastack *LS){
	int64_t v1 = pop(L, LS);
	int64_t v0 = pop(L, LS);
	int t0, t1;
	const glm::mat4x4 * mat = (const glm::mat4x4 *)lastack_value(LS, v1, &t1);
	const glm::vec4 * v = (const glm::vec4 *)lastack_value(LS, v0, &t0);
	if (t0 != LINEAR_TYPE_VEC4 && t1 != LINEAR_TYPE_MAT)
		luaL_error(L, "'%%' operator only support vec4 * mat, type0 is : %d, type1 is : %d", t0, t1);

	glm::vec4 r = *mat * *v;	
	if (!is_zero(r)){
		r /= fabs(r.w);
		r.w = 1.f;
	}

	lastack_pushvec4(LS, &r.x);
}

static void
transposed_matrix(lua_State *L, struct lastack *LS) {
	int t;
	const glm::mat4x4 *mat = (glm::mat4x4*)pop_value(L, LS, &t);
	if (t != LINEAR_TYPE_MAT)
		luaL_error(L, "transposed_matrix need mat4 type, type is : %d", t);
	glm::mat4x4 r = glm::transpose(*mat);
	lastack_pushmatrix(LS, &r[0][0]);
}

static void
inverted_value(lua_State *L, struct lastack *LS) {
	int t;
	const float *value = pop_value(L, LS, &t);
	switch (t)
	{
	case LINEAR_TYPE_MAT: {
		const glm::mat4x4 *m = (const glm::mat4x4*)value;
		glm::mat4x4 r = glm::inverse(*m);		
		lastack_pushmatrix(LS, &r[0][0]);
		break;
	}

	case LINEAR_TYPE_VEC4: {
		glm::vec4 r(-value[0], -value[1], -value[2], value[3]);
		lastack_pushvec4(LS, &r.x);
		break;
	}
	default:
		luaL_error(L, "inverted_value only support mat/vec3/vec4, type is : %d", t);
	}		
}

static void
top_tostring(lua_State *L, struct lastack *LS) {
	int64_t v = lastack_top(LS);
	if (v == 0)
		luaL_error(L, "top empty stack");
	int t = 0;
	const float * r = lastack_value(LS, v, &t);
	value_tostring(L, "", r, t);
}

static void
llookat_matrix(lua_State *L, struct lastack *LS, int direction) {
	int t0, t1;
	const float *at = pop_value(L, LS, &t0);
	const float *eye = pop_value(L, LS, &t1);
	if (t0 != LINEAR_TYPE_VEC4 || t1 != LINEAR_TYPE_VEC4) {
		luaL_error(L, "lookat_matrix, arg0/arg1 need vec4, arg0/arg1 is : %d/%d", t0, t1);
	}	

	glm::mat4x4 m;
	if (direction) {
		const glm::vec3 *dir = (const glm::vec3*)at;
		const glm::vec3 *veye = (const glm::vec3*)eye;
		const glm::vec3 vat = *veye + *dir;
		m = glm::lookAtLH(*veye, vat, glm::vec3(0, 1, 0));
	} else {
		m = glm::lookAtLH(*(const glm::vec3*)eye, *(const glm::vec3*)at, glm::vec3(0, 1, 0));
	}

	lastack_pushmatrix(LS, &m[0][0]);
}

static void
lookat3_matrix(lua_State *L, struct lastack *LS, int direction) {
	int t0, t1, t2;
	const float *at = pop_value(L, LS, &t0);
	const float *eye = pop_value(L, LS, &t1);
	const float *up = pop_value(L, LS, &t2);
	if (t0 != LINEAR_TYPE_VEC4 || t1 != LINEAR_TYPE_VEC4 || t2 != LINEAR_TYPE_VEC4) {
		luaL_error(L, "lookat_matrix, arg0/arg1/arg2 need vec4, arg0/arg1/arg2 is : %d/%d/%d", t0, t1, t1);	
	}

	glm::mat4x4 m;
	if (direction) {
		const glm::vec3 *dir = (const glm::vec3*)at;
		const glm::vec3 *veye = (const glm::vec3*)eye;
		const glm::vec3 vat = *veye + *dir;
		m = glm::lookAtLH(*veye, vat, *(const glm::vec3*)up);
	} else {
		m = glm::lookAtLH(*(const glm::vec3*)eye, *(const glm::vec3*)at, *(const glm::vec3*)up);
	}

	lastack_pushmatrix(LS, &m[0][0]);
}

static void
unpack_top(lua_State *L, struct lastack *LS) {
	int64_t v = pop(L, LS);
	int t = 0;
	const float * r = lastack_value(LS, v, &t);
	switch(t) {
	case LINEAR_TYPE_VEC4:
		lastack_pushnumber(LS, r[0]);
		lastack_pushnumber(LS, r[1]);
		lastack_pushnumber(LS, r[2]);
		lastack_pushnumber(LS, r[3]);
		break;
	case LINEAR_TYPE_MAT:
		lastack_pushvec4(LS, r+0);
		lastack_pushvec4(LS, r+4);
		lastack_pushvec4(LS, r+8);
		lastack_pushvec4(LS, r+12);
		break;
	default:
		luaL_error(L, "Unpack invalid type %s", get_typename(t));
	}
}

struct lnametype_pairs {
	const char* name;
	const char* alias;
	int type;
};

static inline void
get_lnametype_pairs(struct lnametype_pairs *p) {
#define SET(_P, _NAME, _ALIAS, _TYPE) (_P)->name = _NAME; (_P)->alias = _ALIAS; (_P)->type = _TYPE
	SET(p, "mat4x4",	"m",	LINEAR_TYPE_MAT);
	SET(p, "vec4",		"v",	LINEAR_TYPE_VEC4);	
	SET(p, "quat",		"q",	LINEAR_TYPE_QUAT);
	SET(p, "num",		"n",	LINEAR_TYPE_NUM);	
	SET(p, "euler",		"e",	LINEAR_TYPE_EULER);
}

static inline void
convert_to_euler(lua_State *L, struct lastack*LS) {
	int64_t id = pop(L, LS);
	int type;
	const float *value = lastack_value(LS, id, &type);
	glm::vec3 e;
	switch (type) {
		case LINEAR_TYPE_VEC4:{
			glm::vec3 v = glm::normalize(*(glm::vec3*)value);
			glm::quat q(glm::vec3(0, 0, 1), v);
			e = glm::eulerAngles(q);
			break;
		}
		case LINEAR_TYPE_MAT:{
			const glm::mat4x4 *m = (const glm::mat4x4*)value;			
			e = glm::eulerAngles(glm::quat(*m));
			break;
		}
		case LINEAR_TYPE_QUAT:{
			e = glm::eulerAngles(*(glm::quat *)value);			
			break;
		}
		default:
			luaL_error(L, "not support for converting to euler, type is : %d", type);
			break;
	}
	lastack_pusheuler(LS, &e.x);
}

static inline void
convert_to_quaternion(lua_State *L, struct lastack *LS){
	int64_t id = pop(L, LS);
	int type;
	const float *value = lastack_value(LS, id, &type);
	glm::quat q;

	switch (type){
		case LINEAR_TYPE_MAT: 		
			q = glm::quat_cast(*(const glm::mat4x4 *)value);
			break;		
		case LINEAR_TYPE_VEC4:
		case LINEAR_TYPE_EULER:	
			q = glm::quat(*(const glm::vec3*)value);
			break;
		default:
			luaL_error(L, "not support for converting to quaternion, type is : %d", type);
			break;
	}

	lastack_pushquat(LS, &q.x);
}

glm::vec3
to_viewdir(const glm::vec3 &e){
	return is_zero(e) ?
		glm::vec3(0, 0, 1) :
		glm::rotate(glm::quat(e), glm::vec3(0, 0, 1));		
}

static inline void
convert_rotation_to_viewdir(lua_State *L, struct lastack *LS){
	int64_t id = pop(L, LS);
	int type;
	const float *v = lastack_value(LS, id, &type);
	switch (type){
		case LINEAR_TYPE_EULER:
		case LINEAR_TYPE_VEC4:{
			glm::vec4 v4(to_viewdir(*(const glm::vec3*)v), 0);
			lastack_pushvec4(LS, &v4.x);
			break;
		}
		default:
		luaL_error(L, "convect rotation to dir need euler/vec3/vec4 type, type given is : %d", type);
		break;
	}
}

static inline void
convert_viewdir_to_rotation(lua_State *L, struct lastack *LS){
	int64_t id = pop(L, LS);
	int type;
	const float *v = lastack_value(LS, id, &type);
	switch (type){		
		case LINEAR_TYPE_VEC4: {						
			glm::quat q(glm::vec3(0, 0, 1), *(const glm::vec3*)v);
			glm::vec4 e(glm::eulerAngles(q), 0);
			lastack_pushvec4(LS, &e.x);
			break;
		}
	default:
		luaL_error(L, "view dir to rotation only accept vec3/vec4/euler, type given : %d", type);
		break;
	}
}

static inline void
matrix_decompose(const glm::mat4x4 &m, glm::vec4 &scale, glm::vec4 &rot, glm::vec4 &trans) {
	trans = m[3];

	for (int ii = 0; ii < 3; ++ii)
		scale[ii] = glm::length(m[ii]);

	if (scale.x == 0 || scale.y == 0 || scale.z == 0) {
		rot.x = 0;
		rot.y = 0;
		rot.z = 0;
		return;
	}

	glm::mat3x3 rotMat(m);
	for (int ii = 0; ii < 3; ++ii) {
		rotMat[ii] /= scale[ii];		
	}
	rot = glm::vec4(glm::eulerAngles(glm::quat_cast(rotMat)), 0);
}

static inline void
split_mat_to_srt(lua_State *L, struct lastack *LS){
	int64_t id = pop(L, LS);
	int type;
	const float* v = lastack_value(LS, id, &type);
	if (type != LINEAR_TYPE_MAT)
		luaL_error(L, "split operation '~' is only valid for mat4 type, type is : %d", type);
	
	const glm::mat4x4 *mat = (const glm::mat4x4 *)v;
	glm::vec4 scale(1, 1, 1, 0), rotation(0, 0, 0, 0), translate(0, 0, 0, 0);
	matrix_decompose(*mat, scale, rotation, translate);
	
	lastack_pushvec4(LS, &translate.x);
	lastack_pushvec4(LS, &rotation.x);
	lastack_pushvec4(LS, &scale.x);	
}

static inline void
base_axes_from_forward_vector(const glm::vec4& forward, glm::vec4& right, glm::vec4 &up) {
	if (is_zero(forward - glm::vec4(0, 0, 1, 0))) {
		up = glm::vec4(0, 1, 0, 0);
		right = glm::vec4(1, 0, 0, 0);
	} else {

		if (is_zero(forward - glm::vec4(0, 1, 0, 0))) {
			up = glm::vec4(0, 0, 1, 0);
			right = glm::vec4(1, 0, 0, 0);
		} else if (is_zero(forward - glm::vec4(0, -1, 0, 0))) {
			up = glm::vec4(0, 0, -1, 0);
			right = glm::vec4(1, 0, 0, 0);
		} else {
			right = glm::vec4(glm::normalize(glm::cross(glm::vec3(0, 1, 0), *((glm::vec3*)&forward.x))), 0);
			up = glm::vec4(glm::normalize(glm::cross(*(glm::vec3*)(&forward.x), *((glm::vec3*)&right.x))), 0);
		}
	}
}


static inline void
rotation_to_base_axis(lua_State *L, struct lastack *LS){
	int64_t id = pop(L, LS);
	int type;
	const float* v = lastack_value(LS, id, &type);

	glm::vec4 zdir;
	switch (type){
	case LINEAR_TYPE_MAT:
		zdir = (*(glm::mat4x4 *)v) * glm::vec4(0, 0, 1, 0);
		break;
	case LINEAR_TYPE_VEC4:
	case LINEAR_TYPE_EULER:
		zdir = glm::vec4(to_viewdir(*(glm::vec3*)v), 0);
		break;
	case LINEAR_TYPE_QUAT: 
		zdir = (*(glm::quat*)v) * glm::vec4(0, 0, 1, 0);
		break;
	default:
		luaL_error(L, "not support data type, need rotation matrix/quaternion/euler angles, type : %d", type);
		break;
	}
	
	glm::vec4 xdir, ydir;
	base_axes_from_forward_vector(zdir, xdir, ydir);

	lastack_pushvec4(LS, &zdir.x);
	lastack_pushvec4(LS, &ydir.x);
	lastack_pushvec4(LS, &xdir.x);
}

static int
ref_pack_value(lua_State *L) {
	struct refobject * ref = (struct refobject *)lua_touserdata(L, 1);
	struct lastack *LS = ref->LS;
	if (LS == NULL) {
		return luaL_error(L, "Init ref object first : use stack(ref, id, '=')");
	}
	int type;
	const float * v = lastack_value(LS, ref->id, &type);
	float vv[16];
	int n;
	if (type == LINEAR_TYPE_MAT) {
		n = 16;
	} else {
		n = 4;
	}
	int i;
	if (lua_type(L, 2) == LUA_TSTRING) {
		const char * format = lua_tostring(L, 2);
		for (i=0;i<n;i++) {
			if (lua_isnoneornil(L, i+3)) {
				vv[i] = v[i];
			} else {
				switch(format[i]) {
				case 'f':
					vv[i] = luaL_checknumber(L, i+3);
					break;
				case 'd':
					*(uint32_t*)(vv+i) = luaL_checkinteger(L, i+3);
					break;
				default:
					luaL_error(L, "Invalid format %s", format);
				}
			}
		}
	} else {
		for (i=0;i<n;i++) {
			if (lua_isnoneornil(L, i+2)) {
				vv[i] = v[i];
			} else {
				vv[i] = luaL_checknumber(L, i+2);
			}
		}
	}
	lastack_pushobject(LS, vv, type);
	assign_ref(L, ref, lastack_pop(LS));
	lua_settop(L, 1);
	return 1;
}

static int
lassign(lua_State *L) {
	struct refobject * ref = (struct refobject *)lua_touserdata(L, 1);
	struct lastack *LS = ref->LS;
	float v[16];
	int i;
	int top = lua_gettop(L);
	switch(top) {
	case 2:
		break;
	case 4:
		v[3] = 0;
		//fall-through
	case 5:
	case 17:
		if (LS == NULL) {
			return luaL_error(L, "Init ref object first : use stack(ref, id, '=')");
		}
		for (i=2;i<=top;i++)
			v[i-2] = luaL_checknumber(L, i);
		if (top == 17) {
			lastack_pushmatrix(LS, v);
		} else {
			lastack_pushvec4(LS, v);
		}
		assign_ref(L, ref, lastack_pop(LS));
		lua_settop(L, 1);
		return 1;
	default:
		return luaL_error(L, "Invalid arg number %d, support 2/4(vector3)/5(vector4)/17(matrix)", top);
	}
	int type = lua_type(L, 2);
	switch(type) {
	case LUA_TNIL:
	case LUA_TNONE:
		release_ref(L, ref);
		break;
	case LUA_TTABLE:
	case LUA_TNUMBER: {
		if (LS == NULL) {
			return luaL_error(L, "Init ref object first : use stack(ref, id, '=')");
		}
		int64_t rid;
		if (type == LUA_TTABLE) {
			push_value(L, LS, 2);
			rid = pop(L, LS);
		} else {
			rid = get_id(L, 2);
		}
		if (!lastack_sametype(rid, ref->id)) {
			return luaL_error(L, "assign operation : type mismatch");
		}
		assign_ref(L, ref, rid);
		break;
	}
	case LUA_TUSERDATA: {
		struct refobject *rv = (struct refobject *)lua_touserdata(L, 2);
		if (lua_rawlen(L,2) != sizeof(*rv)) {
			return luaL_error(L, "Assign Invalid ref object");
		}
		if (!lastack_sametype(ref->id, rv->id)) {
			return luaL_error(L, "type mismatch");
		}
		if (ref->LS == NULL) {
			ref->LS = rv->LS;
			if (ref->LS) {
				ref->id = lastack_mark(ref->LS, rv->id);
			}
		} else {
			if (rv->LS == NULL) {
				lastack_unmark(ref->LS, ref->id);
				ref->id = rv->id;
			} else {
				if (ref->LS != rv->LS) {
					return luaL_error(L, "Not the same stack");
				}
				lastack_unmark(ref->LS, ref->id);
				ref->id = lastack_mark(ref->LS, rv->id);
			}
		}
		break;
	}
	default:
		return luaL_error(L, "Invalid lua type %s", lua_typename(L, type));
	}
	lua_settop(L, 1);
	return 1;
}

static int
lpointer(lua_State *L) {
	struct refobject * ref = (struct refobject *)lua_touserdata(L, 1);
	const float * v = lastack_value(ref->LS, ref->id, NULL);
	lua_pushlightuserdata(L, (void *)v);
	return 1;
}

struct refobject*
new_refobj(struct lua_State *L, struct lastack *LS, int64_t id){
	struct refobject* ref = (struct refobject*)lua_newuserdata(L, sizeof(struct refobject));
	luaL_setmetatable(L, LINALG_REF);
	ref->LS = LS;
	int t = 0;
	if (lastack_marked(id, &t)) {
		ref->id = id;
	} else {
		int64_t markid = lastack_mark(LS, id);
		if (markid == 0) {
			luaL_error(L, "cound not mark id : %ld", id);
		}
		ref->id = markid;
	}
	return ref;
}

static inline int
const_type(const char* t){
	if (strcmp(t, "vector") == 0) 
		return LINEAR_CONSTANT_IVEC; 
	
	if (strcmp(t, "matrix") == 0) 
		return LINEAR_CONSTANT_IMAT;
	
	if (strcmp(t, "quaternion") == 0)
		return LINEAR_CONSTANT_QUAT;
	
	if (strcmp(t, "euler") == 0) 
		return LINEAR_CONSTANT_EULER;

	return LINEAR_CONSTANT_COUNT;
}

static int
lref(lua_State *L) {
	const char * t = luaL_checkstring(L, 1);
	const bool has_LS = !lua_isnoneornil(L, 2);
	auto LS = has_LS ? ((struct boxstack*)lua_touserdata(L, 2))->LS : nullptr;
	new_refobj(L, LS, lastack_constant(const_type(t)));

	return 1;
}

static int 
lunref(lua_State *L) {
	if(!lua_isuserdata(L,1))
		return luaL_error(L, "unref not userdata. ");
	struct refobject * ref = (struct refobject *)lua_touserdata(L, 1);
	release_ref(L, ref);
	return 0;
}

static int
lisvalid(lua_State *L){
	int type = lua_type(L, 1);
	if (type == LUA_TNUMBER){
		int number = lua_tonumber(L, -1);
		struct boxstack *p = (struct boxstack *)lua_touserdata(L, lua_upvalueindex(1));
		const void *value = lastack_value(p->LS, number, NULL);
		lua_pushboolean(L, value != NULL);
	} else if (type == LUA_TUSERDATA || type == LUA_TLIGHTUSERDATA){
		lua_pushboolean(L, is_ref_obj(L));
	} else {
		lua_pushboolean(L, 0);
	}
	return 1;
}

// fast math functions

static FASTMATH(popnumber)
	int64_t v = pop(L, LS);
	int t = 0;
	const float * r = lastack_value(LS, v, &t);
	if (t != LINEAR_TYPE_NUM)
		luaL_error(L, "Not a number");
	lua_pushnumber(L, r[0]);
	refstack_pop(RS);
	return 1;
}

static FASTMATH(pop)
	pushid(L, pop(L, LS));
	refstack_pop(RS);
	return 1;
}

static FASTMATH(mul)
	mul_2values(L, LS);
	refstack_2_1(RS);
	return 0;
}

static FASTMATH(pointer)
	lua_pushlightuserdata(L, (void *)pop_value(L, LS, NULL));
	refstack_pop(RS);
	return 1;
}

static FASTMATH(table)
	int64_t id = pop(L, LS);
	push_obj_to_lua_table(L, LS, id);
	refstack_pop(RS);
	return 1;
}

static FASTMATH(string)
	top_tostring(L, LS);
	return 1;
}

static FASTMATH(assign)
	int64_t id = pop(L, LS);
	refstack_pop(RS);
	pop(L, LS);
	int index = refstack_topid(RS);
	if (index < 0) {
		luaL_error(L, "need a ref object for assign");
	}
	struct refobject * ref = (struct refobject *)lua_touserdata(L, index);
	assign_ref(L, ref, id);
	refstack_pop(RS);
	return 0;
}

static FASTMATH(dup1)
	int index = 1;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(dup2)
	int index = 2;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(dup3)
	int index = 3;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(dup4)
	int index = 4;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(dup5)
	int index = 5;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(dup6)
	int index = 6;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(dup7)
	int index = 7;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(dup8)
	int index = 8;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(dup9)
	int index = 9;
	int64_t v = lastack_dup(LS, index);
	if (v == 0)
		luaL_error(L, "dup invalid stack index (%d)", index);
	refstack_dup(RS, index);
	return 0;
}

static FASTMATH(swap)
	int64_t v = lastack_swap(LS);
	if (v == 0)
		luaL_error(L, "dup empty stack");
	refstack_swap(RS);
	return 0;
}

static FASTMATH(remove)
	pop(L, LS);
	refstack_pop(RS);
	return 0;
}

static FASTMATH(dot)
	int t0, t1;
	const float * vec1 = pop_value(L, LS, &t0);
	const float * vec2 = pop_value(L, LS, &t1);
	if (t0 != LINEAR_TYPE_VEC4 || t0 != t1)
		luaL_error(L, "dot operation with type mismatch");

	lastack_pushnumber(LS, glm::dot(*((const glm::vec3*)vec1), *((const glm::vec3*)vec2)));
	refstack_2_1(RS);
	return 0;
}

static FASTMATH(cross)
	int t1,t2;
	const float * vec2 = pop_value(L, LS, &t1);
	const float * vec1 = pop_value(L, LS, &t2);
	if (t1 != LINEAR_TYPE_VEC4 || t1 != t2) {
		luaL_error(L, "need vec4 type and cross type mismatch");
	}

	glm::vec4 r(glm::cross(*((const glm::vec3*)vec1), *((const glm::vec3*)vec2)), 0);	
	lastack_pushvec4(LS, &r.x);
	refstack_2_1(RS);
	return 0;
}

static FASTMATH(mulH)
	mulH_2values(L, LS);
	refstack_2_1(RS);
	return 0;
}

static FASTMATH(normalize)
	normalize(L, LS);
	refstack_1_1(RS);
	return 0;
}

static FASTMATH(transposed)
	transposed_matrix(L, LS);
	refstack_1_1(RS);
	return 0;
}

static FASTMATH(inverted)
	inverted_value(L, LS);
	refstack_1_1(RS);
	return 0;
}

static FASTMATH(sub)
	sub_2values(L, LS);
	refstack_2_1(RS);
	return 0;
}

static FASTMATH(add)
	add_2values(L, LS);
	refstack_2_1(RS);
	return 0;
}

static FASTMATH(lookat)
	llookat_matrix(L, LS, 0);
	refstack_2_1(RS);
	return 0;
}

static FASTMATH(lookfrom)
	llookat_matrix(L, LS, 1);
	refstack_2_1(RS);
	return 0;
}

static FASTMATH(lookfrom3)
	lookat3_matrix(L, LS, 1);
	refstack_3_1(RS);
	return 0;
}

static FASTMATH(extract)
	unpack_top(L, LS);
	refstack_pop(RS);
	refstack_push(RS);
	refstack_push(RS);
	refstack_push(RS);
	refstack_push(RS);
	return 0;
}

static FASTMATH(toeuler)
	convert_to_euler(L, LS);
	refstack_1_1(RS);
	return 0;
}

static FASTMATH(toquaternion)
	convert_to_quaternion(L, LS);
	refstack_1_1(RS);
	return 0;
}

static FASTMATH(torotation)
	convert_viewdir_to_rotation(L, LS);
	refstack_1_1(RS);
	return 0;
}

static FASTMATH(todirection)
	convert_rotation_to_viewdir(L, LS);
	refstack_1_1(RS);
	return 0;
}

static FASTMATH(tosrt)
	split_mat_to_srt(L, LS);
	refstack_pop(RS);
	refstack_push(RS);
	refstack_push(RS);
	refstack_push(RS);
	return 0;
}

static FASTMATH(tobase)
	rotation_to_base_axis(L, LS);
	refstack_pop(RS);
	refstack_push(RS);
	refstack_push(RS);
	refstack_push(RS);
	return 0;
}

static FASTMATH(all)
	lua_Integer n = 0;
	lua_newtable(L);
	for (;;) {
		int64_t v = lastack_pop(LS);
		if (v == 0) {
			break;
		}
		int index = refstack_topid(RS);
		if (index < 0) {
			pushid(L, v);
		}
		else {
			lua_pushvalue(L, index);
		}
		lua_rawseti(L, -2, ++n);
		refstack_pop(RS);
	}
	return 1;
}

static FASTMATH(length)
	int64_t id = pop(L, LS);
	int type;
	const glm::vec3 * v = (const glm::vec3 *)lastack_value(LS, id, &type);
	
	lastack_pushnumber(LS, glm::length(*v));
	refstack_pop(RS);
	refstack_push(RS);
	return 0;
}

struct fastmath_function {
	MFunction func;
	const char *desc;
};

static struct fastmath_function s_fastmath[256] = {
	{ NULL, NULL }, //0
	{ NULL, NULL }, //1
	{ NULL, NULL }, //2
	{ NULL, NULL }, //3
	{ NULL, NULL }, //4
	{ NULL, NULL }, //5
	{ NULL, NULL }, //6
	{ NULL, NULL }, //7
	{ NULL, NULL }, //8
	{ NULL, NULL }, //9
	{ NULL, NULL }, //10
	{ NULL, NULL }, //11
	{ NULL, NULL }, //12
	{ NULL, NULL }, //13
	{ NULL, NULL }, //14
	{ NULL, NULL }, //15
	{ NULL, NULL }, //16
	{ NULL, NULL }, //17
	{ NULL, NULL }, //18
	{ NULL, NULL }, //19
	{ NULL, NULL }, //20
	{ NULL, NULL }, //21
	{ NULL, NULL }, //22
	{ NULL, NULL }, //23
	{ NULL, NULL }, //24
	{ NULL, NULL }, //25
	{ NULL, NULL }, //26
	{ NULL, NULL }, //27
	{ NULL, NULL }, //28
	{ NULL, NULL }, //29
	{ NULL, NULL }, //30
	{ NULL, NULL }, //31
	{ NULL, NULL }, //" "
	{ NULL, NULL }, //!
	{ NULL, NULL }, //"
	{ NULL, NULL }, //#
	{ NULL, NULL }, //$
	{ m_mulH, "mulH" }, //%
	{ NULL, NULL }, //&
	{ NULL, NULL }, //'
	{ NULL, NULL }, //(
	{ NULL, NULL }, //)
	{ m_mul, "mul" }, //*
	{ m_add, "add" }, //+
	{ NULL, NULL }, //,
	{ m_sub, "sub" }, //-
	{ m_dot, "dot" }, //.
	{ NULL, NULL }, // /
	{ NULL, NULL }, //0
	{ m_dup1, "dup 1" }, //1
	{ m_dup2, "dup 2" }, //2
	{ m_dup3, "dup 3" }, //3
	{ m_dup4, "dup 4" }, //4
	{ m_dup5, "dup 5" }, //5
	{ m_dup6, "dup 6" }, //6
	{ m_dup7, "dup 7" }, //7
	{ m_dup8, "dup 8" }, //8
	{ m_dup9, "dup 9" }, //9
	{ NULL, NULL }, //:
	{ NULL, NULL }, //;
	{ NULL, NULL }, //<
	{ m_assign, "assign to ref" }, //=
	{ m_extract, "extract" }, //>
	{ NULL, NULL }, //?
	{ m_all, "pop everything" }, //@
	{ NULL, NULL }, //A
	{ NULL, NULL }, //B
	{ NULL, NULL }, //C
	{ m_torotation, "to rotation" }, //D	
	{ NULL, NULL }, //E
	{ NULL, NULL }, //F
	{ NULL, NULL }, //G
	{ NULL, NULL }, //H
	{ NULL, NULL }, //I
	{ NULL, NULL }, //J
	{ NULL, NULL }, //K
	{ m_lookfrom, "look from" }, //L
	{ NULL, NULL }, //M
	{ NULL, NULL }, //N
	{ NULL, NULL }, //O
	{ m_pop, "pop as id" }, //P
	{ NULL, NULL }, //Q
	{ m_remove, "remove" }, //R
	{ m_swap, "swap" }, //S
	{ m_table, "pop as table" }, //T
	{ NULL, NULL }, //U
	{ m_string, "top as string" }, //V
	{ NULL, NULL }, //W
	{ NULL, NULL }, //X
	{ NULL, NULL }, //Y
	{ NULL, NULL }, //Z
	{ NULL, NULL }, //[
	{ NULL, NULL }, //'\\'
	{ NULL, NULL }, //]
	{ NULL, NULL }, //^
	{ NULL, NULL }, //_
	{ NULL, NULL }, //`
	{ NULL, NULL }, //a
	{ m_tobase, "split matrix as x, y, z axis" }, //b
	{ NULL, NULL }, //c
	{ m_todirection, "to direction" }, //d
	{ m_toeuler, "to euler" }, //e
	{ NULL, NULL }, //f
	{ NULL, NULL }, //g
	{ NULL, NULL }, //h
	{ m_inverted, "inverted" }, //i
	{ NULL, NULL }, //j
	{ NULL, NULL }, //k
	{ m_lookat, "look at" }, //l
	{ m_pointer, "pop as pointer" }, //m
	{ m_normalize, "normalize" }, //n
	{ NULL, NULL }, //o
	{ NULL, NULL }, //p
	{ m_toquaternion, "to quaternion" }, //q
	{ NULL, NULL }, //r
	{ NULL, NULL }, //s
	{ m_transposed, "transposed" }, //t
	{ NULL, NULL }, //u
	{ NULL, NULL }, //v
	{ NULL, NULL }, //w
	{ m_cross, "cross" }, //x
	{ NULL, NULL }, //y
	{ NULL, NULL }, //z
	{ NULL, NULL }, //{
	{ NULL, NULL }, //|
	{ NULL, NULL }, //}
	{ m_tosrt, "to srt" }, //~
	{ NULL, NULL }, //127
};

static int
do_command(struct ref_stack *RS, struct lastack *LS, char cmd) {
	MFunction f = s_fastmath[(uint8_t)cmd].func;
	if (f) {
		return f(NULL, LS, RS);
	} else {
		return luaL_error(RS->L, "Unknown command %c", cmd);
	}
}

static int
push_command(struct ref_stack *RS, struct lastack *LS, int index, bool *log) {
	lua_State *L = RS->L;
	int type = lua_type(L, index);
	int pushlog = -1;
	if (*log) {
		pushlog = lastack_gettop(LS);
	}
	switch(type) {
	case LUA_TTABLE:
		push_value(L, LS, index);
		refstack_push(RS);
		break;
	case LUA_TNUMBER:
		if (lastack_pushref(LS, get_id(L, index))) {
			char tmp[64];
			return luaL_error(L, "Invalid id [%s]", lastack_idstring(get_id(L, index), tmp));
		}
		refstack_push(RS);
		break;
	case LUA_TUSERDATA: {
		int64_t id = get_ref_id(L, LS, index);
		if (lastack_pushref(LS, id)) {
			luaL_error(L, "Push invalid ref object");
		}
		refstack_pushref(RS, index);
		break;
	}
	case LUA_TSTRING: {
		size_t sz;
		const char * cmd = luaL_checklstring(L, index, &sz);
		pushlog = -1;
		luaL_checkstack(L, (int)(sz + 20), NULL);
		int i;
		int ret = 0;
		for (i=0;i<(int)sz;i++) {
			int c = cmd[i];
			switch(c) {
			case '#':
				*log = true;
				break;
			default:
				if (*log) {
					const char * desc = NULL;
					if (c>=0 && c<=127) {
						desc = s_fastmath[c].desc;
					}
					if (desc == NULL)
						desc = "undefined";
					printf("MATHLOG [%c %s]: ", c, desc);
					lastack_dump(LS, 0);
					ret += do_command(RS, LS, c);
					printf(" -> ");
					lastack_dump(LS, 0);
					printf("\n");
				} else {
					ret += do_command(RS, LS, c);
				}
				break;
			}
		}
		return ret;
	}
	case LUA_TFUNCTION: {
		// fast call
		MFunction mf = (MFunction)lua_tocfunction(L, index);
		if (mf == NULL) {
			return luaL_error(L, "Not a fast math function");
		}
		return mf(NULL, LS, RS);
	}
	default:
		return luaL_error(L, "Invalid command type %s at %d", lua_typename(L, type), index);
	}
	if (pushlog >= 0) {
		printf("MATHLOG [push]: ");
		lastack_dump(LS, pushlog);
		printf("\n");
	}
	return 0;
}

static int
commandLS(lua_State *L) {
	struct boxstack *bp = (struct boxstack *)lua_touserdata(L, lua_upvalueindex(1));
	struct lastack *LS = bp->LS;
	bool log = false;
	int top = lua_gettop(L);
	int i;
	int ret = 0;
	struct ref_stack RS;
	refstack_init(&RS, L);
	for (i=1;i<=top;i++) {
		ret += push_command(&RS, LS, i, &log);
	}
	return ret;
}

static int
gencommand(lua_State *L) {
	luaL_checkudata(L, 1, LINALG);
	lua_settop(L, 1);
	lua_pushcclosure(L, commandLS, 1);
	return 1;	
}

static int
callLS(lua_State *L) {
	struct boxstack *bp = (struct boxstack *)lua_touserdata(L, 1);
	struct lastack *LS = bp->LS;
	bool log = false;
	int top = lua_gettop(L);
	int i;
	int ret = 0;
	struct ref_stack RS;
	refstack_init(&RS, L);
	// The first is userdata
	for (i=2;i<=top;i++) {
		ret += push_command(&RS, LS, i, &log);
	}
	return ret;
}

static int
new_temp_vector4(lua_State *L) {
	int top = lua_gettop(L);
	if (top == 1) {
		pushid(L, lastack_constant(LINEAR_CONSTANT_IVEC));
		return 1;
	}
	struct lastack* LS = getLS(L, 1);

	float v[4];
	switch(top) {
	case 2:
	{
		const int type = lua_type(L, 2);
		if (type != LUA_TLIGHTUSERDATA && type != LUA_TUSERDATA) {
			luaL_error(L, "invalid data type, need userdata/lightuserdata: %d", type);
		}
		memcpy(v, lua_touserdata(L, 2), sizeof(v));
		break;
	}
	case 4:
		v[3] = 0;
		//fall-through
	case 5:
		for (int i=0;i<top-1;i++) {
			v[i] = luaL_checknumber(L, i+2);
		}
		break;
	default:
		return luaL_error(L, "Need 0/3/4 numbers , stack:vector([x,y,z],[w])");
	}
	lastack_pushvec4(LS, v);
	pushid(L, lastack_pop(LS));
	return 1;
}

static int
new_temp_matrix(lua_State *L) {
	int top = lua_gettop(L);
	if (top == 1) {
		pushid(L, lastack_constant(LINEAR_CONSTANT_IMAT));
		return 1;
	}
	struct lastack* LS = getLS(L, 1);
	float m[16];
	int i;
	switch(top) {
	case 2:
	{
		int type = lua_type(L, 2);
		switch (type) {
		case LUA_TNUMBER:
			// return this id;
			return 1;
		case LUA_TUSERDATA:{
			if (luaL_testudata(L, 2, LINALG_REF)){
				int valuetype;
				memcpy(m, lastack_value(LS, get_ref_id(L, LS, 2), &valuetype), sizeof(m));
			} else {
				memcpy(m, lua_touserdata(L, 2), sizeof(m));
			}
			
			break;
		}
		case LUA_TLIGHTUSERDATA:
			memcpy(m, lua_touserdata(L, 2), sizeof(m));
			break;
		case LUA_TTABLE:
			push_value(L, LS, 2);
			lua_pushinteger(L, pop(L, LS));
			return 1;
		default:
			luaL_error(L, "not support type in arg: %d, type is : %d", top, type);
			break;
		}
	}
		break;
	case 17:
		for (i=0;i<16;i++) {
			m[i] = luaL_checknumber(L, i+2);
		}
		break;
	case 5:
		// 4 vector4
		for (i=0;i<4;i++) {
			int index = i+2;
			int type = lua_type(L, index);
			int64_t id;
			if (type == LUA_TNUMBER) {
				id = luaL_checkinteger(L, index);
			} else if (type == LUA_TUSERDATA) {
				id = get_ref_id(L, LS, index);
			} else {
				return luaL_argerror(L, index, "Need vector");
			}
			const float * temp = lastack_value(LS, id, &type);
			if (type != LINEAR_TYPE_VEC4) {
				return luaL_argerror(L, index, "Not vector4");
			}
			memcpy(&m[4*i], temp, 4 * sizeof(float));
		}
		break;
	default:
		return luaL_error(L, "Need 16 numbers, or 4 vector");
	}
	lastack_pushmatrix(LS, m);
	pushid(L, lastack_pop(LS));
	return 1;
}

static int
new_temp_quaternion(lua_State *L) {
	struct lastack* LS = getLS(L, 1);

	int top = lua_gettop(L);

	if (top == 1) {
		pushid(L, lastack_constant(LINEAR_CONSTANT_QUAT));
		return 1;
	}

	glm::quat q = glm::identity<glm::quat>();
	if (top == 6) {
		luaL_checktype(L, 6, LUA_TBOOLEAN);	// axis radian
		glm::vec3 axis;		
		for (int ii = 0; ii < 3; ++ii) {
			axis[ii] = lua_tonumber(L, ii + 2);
		}

		const float radian = lua_tonumber(L, 5);
		q = glm::angleAxis(radian, axis);
	} else if (top == 5) {
		for (int ii = 0; ii < 4; ++ii) {
			q[ii] = lua_tonumber(L, ii + 2);
		}
	} else if (top == 3) {
		const int type = lua_type(L, 2);
		glm::vec3 axis;
		if (type == LUA_TUSERDATA) {
			if (luaL_testudata(L, 2, LINALG_REF)){
				int valuetype;
				axis = *(const glm::vec3*)lastack_value(LS, get_ref_id(L, LS, 2), &valuetype);
			} else {
				axis = *((const glm::vec3*)lua_touserdata(L, 2));
			}		
		} else if(type == LUA_TLIGHTUSERDATA) {
			axis = *((const glm::vec3*)lua_touserdata(L, 2));
		} else if (type == LUA_TNUMBER) {
			int64_t id = lua_tointeger(L, 2);
			int valuetype;
			axis = *((const glm::vec3 *)lastack_value(LS, id, &valuetype));
		} else if (type == LUA_TTABLE){
			int tblnum = (int)lua_rawlen(L, 2);
			if (tblnum != 3) {
				luaL_error(L, "[second] argument must provied 3 values in table array, only %d provided", tblnum);
			}
			get_table_value(L, 2, 3, axis);			
		} else {
			luaL_error(L, "invalid [second] argument, type = %d, should provided as: \
							userdata/lightuserdata[as float*], stack id or table as array[x, y, z]", type);
		}
		const float radian = lua_tonumber(L, 3);
		q = glm::angleAxis(radian, axis);
	} else if (top == 2) {
		const int type = lua_type(L, 2);
		if (type == LUA_TTABLE) {
			const size_t arraynum = lua_rawlen(L, 2);
			if (arraynum == 4) {
				get_table_value(L, -1, 4, q);
			} else if (arraynum == 3) {
				glm::vec3 euler;
				get_table_value(L, -1, 3, euler);				
				q = glm::quat(euler);
			} else {
				luaL_error(L, "need 3/4 element in array as euler radian or quaternion:%d", arraynum);
			}
		} else if (type == LUA_TUSERDATA) {
			const float* ptr = nullptr;
			if (luaL_testudata(L, 2, LINALG_REF)){
				int valuetype;
				ptr = lastack_value(LS, get_ref_id(L, LS, 2), &valuetype);
			}else{
				ptr = (const float*)lua_touserdata(L, 2);
			}

			q = *((const glm::quat*)ptr);
			
		} else if (type == LUA_TLIGHTUSERDATA){
			q = *((const glm::quat*)lua_touserdata(L, 2));
		}
		else {
			luaL_error(L, "invalid type, only support 'table(array 3/4)' or 'userdata(quaternion data)' : %d", type);
		}
	} else {
		luaL_error(L, "need 5/6 argument, %d provided", top);
	}

	lastack_pushquat(LS, &q.x);
	pushid(L, lastack_pop(LS));

	return 1;
}

static int
new_temp_euler(lua_State *L) {
	struct lastack* LS = getLS(L, 1);

	auto top = lua_gettop(L);
	if (top == 1) {
		pushid(L, lastack_constant(LINEAR_CONSTANT_EULER));
		return 1;
	}

	glm::vec4 v(0, 0, 0, 0);
	assert(top == 4);
	for (int ii = 0; ii < 3; ++ii) {
		v[ii] = lua_tonumber(L, ii + 2);
	}
	
	lastack_pusheuler(LS, &v.x);
	pushid(L, lastack_pop(LS));
	return 1;
}

static int
lsrt_matrix(lua_State *L) {
	const int numarg = lua_gettop(L);
	if (numarg < 1) {
		luaL_error(L, "invalid argument, at least 1:%d", numarg);
	}

	struct lastack* LS = getLS(L, 1);

	switch (numarg) {
	case 1:
	{
		glm::mat4x4 srt(1);
		lastack_pushmatrix(LS, &(srt[0][0]));
	}
	break;
	case 2:
	{
		luaL_checktype(L, 2, LUA_TTABLE);
		push_srt_from_table(L, LS, 2);
	}
	break;
	case 4:
		make_srt(LS, 
			extract_scale(L, LS, 2), 
			extract_rotation_mat(L, LS, 3), 
			extract_translate(L, LS, 4));
	break;

	default:
		luaL_error(L, "only support 1(const)/2({s=...,r=...,t=...})/4(s,r,t) argument:%d", numarg);
		break;
	}	
	
	pushid(L, pop(L, LS));
	return 1;
}

static int
lmul_srtmat(lua_State* L) {
	struct lastack* LS = getLS(L, 1);

	const glm::mat4x4 parent_mat = get_mat_value(L, LS, 2);
	const glm::mat4x4 mat = get_mat_value(L, LS, 3);

	const bool ignore_parentscale = lua_isnoneornil(L, 4) ? false : lua_toboolean(L, 4);

	auto m = parent_mat * mat;

	if (ignore_parentscale) {
		for (int ii = 0; ii < 3; ++ii) {
			auto s = glm::length(parent_mat[ii]);
			if (is_zero(s))
				s = 1;

			m[ii] *= 1 / s;
		}
	}

	lastack_pushmatrix(LS, &m[0].x);
	pushid(L, pop(L, LS));
	
	return 1;
}

static int
lview_proj(lua_State *L) {
	const int numarg = lua_gettop(L);
	if (numarg < 2) {
		return luaL_error(L, "argument should provided as: \
							camera[view matrix, can be nil],\
							frustum[project, can be nil],\
							combine[view&proj or not], \
							but camera, frustum must provided one of them.\
							%d provided", numarg);
	}

	struct boxstack *bp = (struct boxstack*)lua_touserdata(L, 1);
	lastack *LS = bp->LS;

	glm::mat4x4 viewmat;
	const bool hasviewmat = !lua_isnil(L, 2);
	if (hasviewmat) {
		luaL_checktype(L, 2, LUA_TTABLE);	// view matrix

		lua_getfield(L, 2, "viewdir");		
		const glm::vec3 viewdir = get_vec_value(L, LS, -1);
		lua_pop(L, 1);
		lua_getfield(L, 2, "eyepos");
		const glm::vec3 eyepos = get_vec_value(L, LS, -1);
		lua_pop(L, 1);

		const glm::vec3 updir = (lua_getfield(L, 2, "updir") == LUA_TNIL) ?
			glm::vec3(0, 1, 0) : get_vec_value(L, LS, -1);
		lua_pop(L, 1);

		viewmat = glm::lookAtLH(eyepos, eyepos + viewdir, updir);
	}

	glm::mat4x4 projmat;
	const bool hasprojmat = !lua_isnil(L, 3);
	if (hasprojmat) {
		luaL_checktype(L, 3, LUA_TTABLE);
		projmat = create_proj_mat(L, LS, 3);
	}

	const bool combine = lua_isnoneornil(L, 4) ? false : (!!lua_toboolean(L, 4));

	int numresult = 0;

	if (hasviewmat) {
		lastack_pushmatrix(LS, &viewmat[0][0]);
		pushid(L, pop(L, LS));
		++numresult;
	}

	if (hasprojmat) {
		lastack_pushmatrix(LS, &projmat[0][0]);
		pushid(L, pop(L, LS));
		++numresult;
	}

	if (combine) {
		if (hasviewmat && hasprojmat) {
			auto viewproj = projmat * viewmat;
			lastack_pushmatrix(LS, &viewproj[0][0]);
			pushid(L, pop(L, LS));
			return 3;
		}

		luaL_error(L, "one of view or proj matrix is not provided, matrix are not enough to combine");
	}

	assert(numresult >= 1);
	return numresult;
}

template<typename T>
static T 
get_value(lua_State *L, struct lastack *LS, int index) {
	switch (lua_type(L, index)) {
	case LUA_TUSERDATA:
	case LUA_TNUMBER:
	{
		int type;
		return *((const T*)lastack_value(LS, get_stack_id(L, LS, index), &type));
	}
	case LUA_TTABLE:
	{
		T v;		
		const int len = (int)lua_rawlen(L, index);
		get_table_value(L, index, len, v);
		return v;
	}
	default:
		luaL_error(L, "invalid data type, only support table/userdata(refvalue)/stack number");
		return T(0);
	}
}

glm::vec4 
get_vec_value(lua_State *L, struct lastack *LS, int index) {
	return get_value<glm::vec4>(L, LS, index);
}

glm::mat4x4
get_mat_value(lua_State* L, struct lastack* LS, int index){
	return get_value<glm::mat4x4>(L, LS, index);
}

static int
llength(lua_State *L) {
	struct lastack* LS = getLS(L, 1);

	const int numarg = lua_gettop(L);
	float len = 0.0f;
	switch (numarg) {
	case 2:
	{
		glm::vec4 v = get_vec_value(L, LS, 2);
		len = glm::length(v);
	}
		break;
	case 3:
	{
		auto lhs = get_vec_value(L, LS, 2);
		auto rhs = get_vec_value(L, LS, 3);

		len = glm::length(lhs - rhs);
	}
		break;
	default:
		luaL_error(L, "only support 2/3 arguments, 2 for (ms, vec4), 3 for (ms, vec4, vec4) as length([2 - 3]), %d provided", numarg);
		break;
	}
	
	lua_pushnumber(L, len);
	return 1;
}

static int
ldot(lua_State *L) {
	struct lastack* LS = getLS(L, 1);

	const int numarg = lua_gettop(L);
	if (numarg != 3) {
		luaL_error(L, "only support 2 arguments:%d", numarg - 1);
	}

	const auto v0 = get_vec_value(L, LS, 2);
	const auto v1 = get_vec_value(L, LS, 3);

	lua_pushnumber(L, glm::dot(v0, v1));
	return 1;
}

static int
lis_parallel(lua_State *L) {
	struct lastack* LS = getLS(L, 1);

	const int numarg = lua_gettop(L);
	if (numarg < 3) {
		luaL_error(L, "need argument: v0, v1, and threshold value[opt], argument provided:%d", numarg);
	}

	const auto v0 = get_vec_value(L, LS, 2);
	const auto v1 = get_vec_value(L, LS, 3);

	const float threshold = luaL_optnumber(L, 4, 0.01f);

	lua_pushboolean(L, is_zero(glm::cross(*tov3(v0), *tov3(v1)), glm::vec3(threshold)));
	return 1;
}

static int
lscreen_point_to_3d(lua_State *L) {
	const int numarg = lua_gettop(L);
	if (numarg < 4) {
		luaL_error(L, "at least 4 arguments, %d provided. arguments: (camera component[with eyepos/viewdir/frustum], viewport[w, h], point at 2d", numarg);
	}

	struct lastack* LS = getLS(L, 1);

	// camera
	luaL_checktype(L, 2, LUA_TTABLE);

	lua_getfield(L, 2, "frustum");
	auto matProj = create_proj_mat(L, LS, -1);
	lua_pop(L, 1);

	int type;
	lua_getfield(L, 2, "eyepos");
	const glm::vec3 *eyepos = (const glm::vec3*)lastack_value(LS, get_stack_id(L, LS, -1), &type);
	lua_pop(L, 1);

	lua_getfield(L, 2, "viewdir");
	const glm::vec3 *viewdir = (const glm::vec3*)lastack_value(LS, get_stack_id(L, LS, -1), &type);
	lua_pop(L, 1);

	lua_getfield(L, 2, "updir");
	const glm::vec3 *updir = (const glm::vec3*)lastack_value(LS, get_stack_id(L, LS, -1), &type);
	lua_pop(L, 1);

	glm::mat4x4 matView = glm::lookAtLH(*eyepos, *eyepos + *viewdir, *updir);

	// view rect
	luaL_checktype(L, 3, LUA_TTABLE);
	lua_getfield(L, 3, "w");
	const float width = lua_tonumber(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, 3, "h");
	const float height = lua_tonumber(L, -1);
	lua_pop(L, 1);


	//////////////////////////////////////////////////////////////////////////

	const glm::mat4x4 matInverseVP = glm::inverse(matProj * matView);


	// get 2d point, point.z is the depth in ndc space
	const int point_start_idx = 3;
	const int num2dpoint = numarg - point_start_idx;

	for (int ii = 0; ii < num2dpoint; ++ii) {
		auto fetchpoint = [L, width, height](int index) {
			glm::vec4 p;
			for (int jj = 0; jj < 3; ++jj) {
				lua_geti(L, index, jj+1);
				p[jj] = lua_tonumber(L, -1);
				lua_pop(L, 1);
			}
			auto remap0_1 = [](float v) {
				return v * 2.f - 1.f;
			};
			p.x = remap0_1(p.x / width);
			p.y = remap0_1((height - p.y) / height);
			p.w = 1;
			return p;
		};

		glm::vec4 p = fetchpoint(ii + 1 + point_start_idx);
		auto tmp = matInverseVP * p;
		p = tmp / tmp.w;

		lastack_pushvec4(LS, &p.x);
		pushid(L, pop(L, LS));
	}

	return num2dpoint;
}

static int
llhs_rotation(lua_State *L) {
	struct lastack* LS = getLS(L, 1);

	glm::vec4 euler = get_vec_value(L, LS, 2);
	const glm::mat3 scale(
		-1, 0, 0,
		0, 1, 0,
		0, 0, 1);

	const glm::mat3 r_mat = glm::mat3(glm::quat(euler));
	
	const glm::mat3 l_mat = scale * r_mat * scale;
	
	glm::vec3 neweuler = glm::eulerAngles(glm::quat_cast(l_mat));
	lua_createtable(L, 3, 0);
	for (int ii = 0; ii < 3; ++ii) {
		lua_pushnumber(L, neweuler[ii]);
		lua_seti(L, -2, ii + 1);
	}

	return 1;
}

static int
llhs_matrix(lua_State *L) {
	struct lastack* LS = getLS(L, 1);

	const glm::mat3 scale(
		-1, 0, 0,
		0, 1, 0,
		0, 0, 1);
		

	const auto type = lua_type(L, 2);
	glm::mat4 r_mat(1);
	switch (type) {
	case LUA_TNUMBER:
	case LUA_TUSERDATA: {
		int datatype = 0;
		const float* v = lastack_value(LS, get_stack_id(L, LS, 2), &datatype);
		if (datatype != LINEAR_TYPE_MAT) {
			luaL_error(L, "not support datatype:%d", datatype);
		}

		r_mat = *(glm::mat4*)v;
	}
		break;
	case LUA_TTABLE: {
		const auto checktype = lua_getfield(L, 2, "s");
		lua_pop(L, 1);
		if (checktype == LUA_TTABLE) {
			lua_getfield(L, 2, "s");
			const glm::vec3 scale = extract_scale(L, LS, -1);
			lua_pop(L, 1);

			lua_getfield(L, 2, "r");
			const glm::mat4x4 rotMat = extract_rotation_mat(L, LS, -1);
			lua_pop(L, 1);

			lua_getfield(L, 2, "t");
			const glm::vec3 translate = extract_translate(L, LS, -1);
			lua_pop(L, 1);

			
			r_mat[0][0] = scale[0];
			r_mat[1][1] = scale[1];
			r_mat[2][2] = scale[2];
			r_mat = rotMat * r_mat;
			r_mat[3] = glm::vec4(translate, 1);
		} else {
			for (int ii = 0; ii < 4; ++ii) {
				for (int jj = 0; jj < 4; ++jj) {
					lua_geti(L, 2, ii * 4 + jj + 1);
					r_mat[ii][jj] = lua_tonumber(L, -1);
					lua_pop(L, 1);
				}				
			}
		}
	}
		break;
	default:
		break;
	}

	const glm::mat3 rot = r_mat;
	glm::mat4 l_mat = scale * rot * scale;
	const glm::vec4 &translate = r_mat[3];
	l_mat[3] = glm::vec4(-translate[0], translate[1], translate[2], 1);

	lastack_pushmatrix(LS, (const float*)(&l_mat));
	lua_pushinteger(L, lastack_pop(LS));
	return 1;
}

static int
llerp(lua_State* L) {
	struct lastack* LS = getLS(L, 1);

	const auto v0 = get_vec_value(L, LS, 2);
	const auto v1 = get_vec_value(L, LS, 3);

	const auto ratio = lua_tonumber(L, 4);

	const auto l = glm::vec4(*tov3(v0) + (*tov3(v1) - *tov3(v0)) * (float)ratio, 0.f);

	lastack_pushvec4(LS, &l.x);
	lua_pushinteger(L, lastack_pop(LS));
	return 1;
}

static int
lequal(lua_State* L) {
	struct lastack* LS = getLS(L, 1);

	const int lhstype = lua_type(L, 2);
	const int rhstype = lua_type(L, 3);
	if (lhstype != rhstype) {
		lua_pushboolean(L, false);
		return 1;
	}

	if (lhstype == LUA_TNUMBER || lhstype == LUA_TUSERDATA) {
		int type1;
		const float* lhs = lastack_value(LS, get_ref_id(L, LS, 2), &type1);
		int type2;
		const float* rhs = lastack_value(LS, get_ref_id(L, LS, 3), &type2);

		if (type1 != type2) {
			lua_pushboolean(L, false);
			return 1;
		}

		const int num = type1 == LINEAR_CONSTANT_IMAT ? 16 : 4;
		for (int ii = 0; ii < num; ++ii) {
			if (!is_zero(lhs[ii] - rhs[ii])) {
				lua_pushboolean(L, false);
				return 1;
			}
		}

		lua_pushboolean(L, true);
		return 1;
	} else if (lhstype == LUA_TTABLE){
		const int len1 = (int)lua_rawlen(L, 2);
		const int len2 = (int)lua_rawlen(L, 3);

		if (len1 != len2) {
			lua_pushboolean(L, false);
			return 1;
		}

		float v1[16], v2[16];
		for (int ii = 0; ii < len1; ++ii) {
			lua_geti(L, 2, ii + 1);
			v1[ii] = lua_tonumber(L, -1);
			lua_pop(L, 1);

			lua_geti(L, 3, ii + 1);
			v2[ii] = lua_tonumber(L, -1);
			lua_pop(L, 1);
		}
		
		for (int ii = 0; ii < len1; ++ii) {
			if (!is_zero(v1[ii] - v2[ii])) {
				lua_pushboolean(L, false);
				return 1;
			}
		}

		lua_pushboolean(L, true);
		return 1;
	} else {
		luaL_error(L, "not support type:%d", lhstype);
	}

	return 0;
}

static int
lbase_axes_from_forward_vector(lua_State *L) {
	struct boxstack *bp = (struct boxstack *)luaL_checkudata(L, 1, LINALG);
	struct lastack* LS = bp->LS;

	auto forwardid = get_stack_id(L, LS, 2);
	int type;
	const glm::vec4 *forward = (const glm::vec4 *)lastack_value(LS, forwardid, &type);
	glm::vec4 right, up;
	base_axes_from_forward_vector(*forward, right, up);

	lastack_pushvec4(LS, &right.x);
	pushid(L, pop(L, LS));

	lastack_pushvec4(LS, &up.x);
	pushid(L, pop(L, LS));
	return 2;
}

static int
lstackrefobject(lua_State *L) {
	lua_settop(L, 2);
	lua_insert(L, 1);	// type stack
	return lref(L);
}

static int
lnew(lua_State *L) {	
	struct boxstack *bp = (struct boxstack *)lua_newuserdata(L, sizeof(*bp));

	bp->LS = NULL;
	if (luaL_getmetatable(L, LINALG)) {
		lua_setmetatable(L, -2);
		bp->LS = lastack_new();
		return 1;
	} 
	
	return luaL_error(L, "not %s metatable register!", LINALG);
}

static int
lreset(lua_State *L) {
	struct lastack *LS = getLS(L, 1);
	lastack_reset(LS);
	return 0;
}

static int
lprint(lua_State *L) {
	struct lastack *LS = getLS(L, 1);
	lastack_print(LS);
	return 0;
}

static int
lcommand_description(lua_State *L){
	lua_newtable(L);
	for (size_t c = 0; c < 128; ++c) {
		const char* desc = s_fastmath[c].desc;
		if (desc) {
			lua_pushstring(L, desc);
			char name[2] = { (char)(unsigned char)c, 0 };
			lua_setfield(L, -2, name);
		}
	}

	return 1;
}

#include <tuple>

static int
lconstant(lua_State *L) {
	const char *what = luaL_checkstring(L, 1);	
	int cons;
	if (strcmp(what, "identvec") == 0) {
		cons = LINEAR_CONSTANT_IVEC;
	} else if (strcmp(what, "identmat") == 0) {
		cons = LINEAR_CONSTANT_IMAT;
	} else if (strcmp(what, "identnum") == 0) {
		cons = LINEAR_CONSTANT_NUM;
	} else if (strcmp(what, "identquat") == 0) {
		cons = LINEAR_CONSTANT_QUAT;
	} else if (strcmp(what, "identeuler") == 0) {
		cons = LINEAR_CONSTANT_EULER;
	} else {
		return luaL_error(L, "Invalid constant %s", what);
	}
	pushid(L, lastack_constant(cons));
	return 1;
}

static int
ltype(lua_State *L) {
	int64_t id;
	switch(lua_type(L, 1)) {
	case LUA_TNUMBER:
		id = get_id(L, 1);
		break;
	case LUA_TUSERDATA: {
		struct refobject * ref = (struct refobject *)lua_touserdata(L, 1);
		if (lua_rawlen(L,1) != sizeof(*ref)) {
			return luaL_error(L, "Get invalid ref object type");
		}
		id = ref->id;
		break;
	}
	default:
		return luaL_error(L, "Invalid lua type %s", lua_typename(L, 1));
	}
	int t;
	int marked = lastack_marked(id, &t);
	lua_pushstring(L, get_typename(t));
	lua_pushboolean(L, marked);

	return 2;
}

static int
lhomogeneous_depth(lua_State *L){
	int num = lua_gettop(L);
	if (num > 0){
		g_default_homogeneous_depth = lua_toboolean(L, 1) != 0;	
		return 0;
	}

	lua_pushboolean(L, g_default_homogeneous_depth ? 1 : 0);
	return 1;
}

static int
lstacksize(lua_State *L) {
	struct boxstack *bp = (struct boxstack *)luaL_checkudata(L, 1, LINALG);
	struct lastack* LS = bp->LS;
	lua_pushinteger(L, lastack_size(LS));
	return 1;
}

static void
register_linalg_mt(lua_State *L) {
	if (luaL_newmetatable(L, LINALG)) {
		luaL_Reg l[] = {
			{ "__gc", delLS },
			{ "__call", callLS },
			{ MFUNCTION(mul) },
			{ MFUNCTION(pop) },
			{ MFUNCTION(popnumber) },
			{ MFUNCTION(toquaternion)},
			{ MFUNCTION(lookfrom3)},
			{ MFUNCTION(length)},
			{ "stacksize", lstacksize },
			{ "ref", lstackrefobject },
			{ "command", gencommand },
			{ "vector", new_temp_vector4 },	// equivalent to stack( { x,y,z,w }, "P" )
			{ "matrix", new_temp_matrix },
			{ "quaternion", new_temp_quaternion},
			{ "euler", new_temp_euler},
			{ "base_axes", lbase_axes_from_forward_vector},
			{ "srtmat", lsrt_matrix },
			{ "mul_srtmat", lmul_srtmat},
			{ "view_proj", lview_proj},
			{ "length", llength},
			{ "dot", ldot},
			{ "is_parallel", lis_parallel},
			{ "screenpt_to_3d", lscreen_point_to_3d},
			{ "lhs_rotation", llhs_rotation},
			{ "lhs_mat", llhs_matrix},
			{ "lerp", llerp},
			{ "equal", lequal},
			{ NULL, NULL },
		};
		luaL_setfuncs(L, l, 0);
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
	}
}

extern "C" {
	LUAMOD_API int
	luaopen_math3d(lua_State *L) {
		luaL_checkversion(L);
		luaL_Reg ref[] = {
			{ "__tostring", lreftostring },
			{ "__call", lassign },
			{ "__bnot", lpointer },
			{ "value", ref_to_value },
			{ "unpack", ref_unpack_value },
			{ "id", ref_clone_value },
			{ "pack", ref_pack_value },
			{ NULL, NULL },
		};
		luaL_newmetatable(L, LINALG_REF);
		luaL_setfuncs(L, ref, 0);
		lua_pushvalue(L, -1);
		lua_setfield(L, -2, "__index");
		lua_pop(L, 1);


		register_linalg_mt(L);

		luaL_Reg l[] = {
			{ "new", lnew },
			{ "reset", lreset },
			{ "constant", lconstant },
			{ "print", lprint },	// for debug
			{ "type", ltype },
			{ "ref", lref },
			{ "unref",lunref },
			{ "isvalid", lisvalid},
			{ "cmd_description", lcommand_description},
			{ "homogeneous_depth", lhomogeneous_depth},
			{ NULL, NULL },
		};
		luaL_newlib(L, l);
		return 1;
	}
}