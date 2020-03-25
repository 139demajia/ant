#define LUA_LIB
#include <lua.hpp>

#include "hierarchy.h"
#include "meshbase/meshbase.h"

#include <ozz/animation/runtime/animation.h>
#include <ozz/animation/runtime/sampling_job.h>
#include <ozz/animation/runtime/local_to_model_job.h>
#include <ozz/animation/runtime/blending_job.h>
#include <ozz/animation/runtime/skeleton.h>

#include <ozz/geometry/runtime/skinning_job.h>
#include <ozz/base/platform.h>

#include <ozz/base/maths/soa_transform.h>
#include <ozz/base/maths/soa_float4x4.h>
#include <ozz/base/maths/simd_quaternion.h>

#include <ozz/animation/runtime/ik_two_bone_job.h>
#include <ozz/animation/runtime/ik_aim_job.h>

#include <ozz/base/memory/allocator.h>
#include <ozz/base/io/stream.h>
#include <ozz/base/io/archive.h>
#include <ozz/base/containers/vector.h>
#include <ozz/base/containers/map.h>
#include <ozz/base/maths/math_ex.h>

#include <../samples/framework/mesh.h>

// glm
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

// stl
#include <string>
#include <cstring>
#include <algorithm>
#include <sstream>

template <typename T>
class luaClass {
protected:
	typedef luaClass<T> base_type;
	template <typename ...Args>
	static T* constructor(lua_State* L, Args ...args) {
		T* o = (T*)lua_newuserdatauv(L, sizeof(T), 0);
		new (o) T(args...);
		reigister_mt(L, nullptr);
		lua_setmetatable(L, -2);
		return o;
	}
	static void set_method(lua_State* L, luaL_Reg l[]) {
		if (lua_getmetatable(L, -1)) {
			luaL_setfuncs(L, l, 0);
			lua_pop(L, 1);
		}
	}

	static void reigister_mt(lua_State *L, luaL_Reg *ll){
		if (luaL_newmetatable(L, kLuaName)) {
			lua_pushvalue(L, -1);
			lua_setfield(L, -2, "__index");
			luaL_Reg l[] = {
				{"__gc", destructor},
				{nullptr, nullptr},
			};
			luaL_setfuncs(L, l, 0);

			if (ll)
				luaL_setfuncs(L, ll, 0);
		}
	}
protected:
	static const char kLuaName[];
private:
	static int destructor(lua_State* L) {
		get(L, 1)->~T();
		return 0;
	}
public:
	static T* get(lua_State* L, int idx) {
		return (T*)luaL_testudata(L, idx, kLuaName);
	}

	static int getMT(lua_State *L){
		luaL_getmetatable(L, kLuaName);
		return 1;
	}
};
#define REGISTER_LUA_CLASS(C) template<> const char luaClass<C>::kLuaName[] = #C;

struct ozzJointRemap : public luaClass<ozzJointRemap> {
	ozz::Vector<uint16_t>::Std joints;
	ozzJointRemap()
	: joints()
	{ }
	~ozzJointRemap()
	{ }

	static int create(lua_State* L) {
		ozzJointRemap* self = base_type::constructor(L);
		switch (lua_type(L, 1)) {
		case LUA_TTABLE: {
			size_t n = (size_t)lua_rawlen(L, 1);
			self->joints.resize(n);
			for (size_t i = 0; i < n; ++i){
				lua_geti(L, 1, i+1);
				self->joints[i] = (uint16_t)luaL_checkinteger(L, -1);
				lua_pop(L, 1);
			}
			break;
		}
		case LUA_TLIGHTUSERDATA: {
			const size_t jointnum = (size_t)luaL_checkinteger(L, 2);
			self->joints.resize(jointnum);
			const uint16_t *p = (const uint16_t*)lua_touserdata(L, 1);
			memcpy(&self->joints.front(), p, jointnum * sizeof(uint16_t));
			break;
		}
		default:
			return luaL_error(L, "not support type in argument 1");
		}
		return 1;
	}
};
REGISTER_LUA_CLASS(ozzJointRemap)


template <typename T>
struct ozzBindposeT : public bindpose, luaClass<T> {
public:
	typedef luaClass<T> base_type;

	ozzBindposeT(size_t numjoints)
		: bindpose(numjoints)
	{}

	ozzBindposeT(size_t numjoints, const float* data)
		: bindpose(numjoints)
	{
		memcpy(&(*this)[0], data, sizeof(ozz::math::Float4x4) * numjoints);
	}

	static bindpose* getBP(lua_State *L, int index){
		#ifdef _DEBUG
			assert(luaL_testudata(L, index, "ozzBindpose") || luaL_testudata(L, index, "ozzPoseResult"));
		#endif
		return (bindpose*)lua_touserdata(L, index);
	}

protected:
	static int lcount(lua_State* L) {
		auto bp = (bindpose*)lua_touserdata(L, 1);
		lua_pushinteger(L, bp->size());
		return 1;
	}

	static int ljoint(lua_State *L){
		auto bp = (bindpose*)lua_touserdata(L, 1);
		const auto jointidx = (uint32_t)lua_tointeger(L, 2) - 1;
		if (jointidx < 0 || jointidx > bp->size()){
			luaL_error(L, "invalid joint index:%d", jointidx);
		}

		float * r = (float*)lua_touserdata(L, 3);
		const ozz::math::Float4x4& trans = (*bp)[jointidx];
		assert(sizeof(trans) <= sizeof(float) * 16);
		memcpy(r, &trans, sizeof(trans));
		return 0;
	}
public:
	static int create(lua_State* L) {
		lua_Integer numjoints = luaL_checkinteger(L, 1);
		if (numjoints <= 0) {
			luaL_error(L, "joints number should be > 0");
			return 0;
		}
		switch (lua_type(L, 2)) {
		case LUA_TNIL:
		case LUA_TNONE:
			base_type::constructor(L, (size_t)numjoints);
			break;
		case LUA_TSTRING: {
			size_t size = 0;
			const float* data = (const float*)lua_tolstring(L, 2, &size);
			if (size != sizeof(ozz::math::Float4x4) * numjoints) {
				return luaL_error(L, "init data size is not valid, need:%d", sizeof(ozz::math::Float4x4) * numjoints);
			}
			base_type::constructor(L, (size_t)numjoints, data);
			break;
		}
		case LUA_TUSERDATA:
		case LUA_TLIGHTUSERDATA: {
			const float* data = (const float*)lua_touserdata(L, 2);
			base_type::constructor(L, (size_t)numjoints, data);
			break;
		}
		default:
			return luaL_error(L, "argument 2 is not support type, only support string/userdata/light userdata");
		}
		return 1;
	}

	static void registerBindposeMetatable(lua_State *L){
		luaL_Reg l[] = {
			{"count", lcount},
			{"joint", ljoint},
			{nullptr, nullptr,}
		};
		base_type::reigister_mt(L, l);
		lua_pop(L, 1);
	}
};

__declspec (align(8))
struct ozzBindpose : public ozzBindposeT<ozzBindpose>{
	ozzBindpose(size_t numjoints):ozzBindposeT<ozzBindpose>(numjoints){}
	ozzBindpose(size_t numjoints, const float *data):ozzBindposeT<ozzBindpose>(numjoints, data){}
};
REGISTER_LUA_CLASS(ozzBindpose)

extern bool
do_ik(lua_State* L,
	const ozz::animation::Skeleton *ske,
	bindpose_soa &bp_soa, 
	bindpose &result_pose);

struct ozzAllocator : public luaClass<ozzAllocator> {
	void* v;
	ozzAllocator(size_t size, size_t alignment)
	: v(ozz::memory::default_allocator()->Allocate(size, alignment))
	{ }
	~ozzAllocator() {
		ozz::memory::default_allocator()->Deallocate(v);
	}

	static int lpointer(lua_State* L) {
		lua_pushlightuserdata(L, base_type::get(L, 1)->v);
		return 1;
	}
	static int create(lua_State* L) {
		const size_t sizebytes = (size_t)luaL_checkinteger(L, 1);
		const size_t aligned = (size_t)luaL_optinteger(L, 2, 4);
		base_type::constructor(L, sizebytes, aligned);
		luaL_Reg l[] = {
			{"pointer", lpointer},
			{nullptr, nullptr},
		};
		base_type::set_method(L, l);
		return 1;
	}
};
REGISTER_LUA_CLASS(ozzAllocator)

struct ozzSamplingCache : public luaClass<ozzSamplingCache> {
	ozz::animation::SamplingCache* v;
	ozzSamplingCache(int max_tracks)
	: v(OZZ_NEW(ozz::memory::default_allocator(), ozz::animation::SamplingCache)(max_tracks))
	{ }
	~ozzSamplingCache() {
		OZZ_DELETE(ozz::memory::default_allocator(), v);
	}
	static int create(lua_State* L) {
		int max_tracks = (int)luaL_optinteger(L, 1, 0);
		base_type::constructor(L, max_tracks);
		return 1;
	}
};
REGISTER_LUA_CLASS(ozzSamplingCache)

struct ozzAnimation : public luaClass<ozzAnimation> {
	ozz::animation::Animation* v;
	ozzAnimation()
	: v(OZZ_NEW(ozz::memory::default_allocator(), ozz::animation::Animation)())
	{ }
	~ozzAnimation() {
		OZZ_DELETE(ozz::memory::default_allocator(), v);
	}

	static int lduration(lua_State *L) {
		lua_pushnumber(L, base_type::get(L, 1)->v->duration());
		return 1;
	}
	static int lsize(lua_State *L) {
		lua_pushinteger(L, base_type::get(L, 1)->v->size());
		return 1;
	}

	static int lnum_tracks(lua_State *L){
		lua_pushinteger(L, base_type::get(L, 1)->v->num_tracks());
		return 1;
	}

	static int lname(lua_State *L){
		lua_pushstring(L, base_type::get(L, 1)->v->name());
		return 1;
	}
	
	static int create(lua_State* L) {
		const char* path = luaL_checkstring(L, 1);
		ozzAnimation* self = base_type::constructor(L);
		luaL_Reg l[] = {		
			{"duration", lduration},
			{"num_tracks", lnum_tracks},
			{"name", lname},
			{"size", lsize},
			{nullptr, nullptr},
		};
		base_type::set_method(L, l);

		ozz::io::File file(path, "rb");
		if (!file.opened()) {
			luaL_error(L, "file could not open : %s", path);
		}
		ozz::io::IArchive archive(&file);
		if (!archive.TestTag<ozz::animation::Animation>()) {		
			luaL_error(L, "file is not ozz::animation, file : %s", path);
		}
		archive >> *(self->v);
		return 1;
	}
};
REGISTER_LUA_CLASS(ozzAnimation)

__declspec (align(8))
struct ozzPoseResult : public ozzBindposeT<ozzPoseResult> {
public:
	typedef luaClass<ozzPoseResult> luaClassType;

	ozz::Vector<bindpose_soa>::Std  m_results;
	ozz::Vector<ozz::animation::BlendingJob::Layer>::Std m_layers;
	ozz::animation::Skeleton*   m_ske;
	bool	m_fix_root;
	ozzPoseResult(size_t numjoints)
		: ozzBindposeT<ozzPoseResult>(numjoints)
		, m_ske(nullptr)
		, m_fix_root(true)
	{}

	ozzPoseResult(size_t numjoints, const float *data)
		: ozzBindposeT<ozzPoseResult>(numjoints, data)
		, m_ske(nullptr)
		, m_fix_root(true)
	{}
private:
	void _push_pose(bindpose_soa const& pose, float weight) {
		m_results.emplace_back(pose);
		ozz::animation::BlendingJob::Layer layer;
		layer.weight = weight;
		layer.transform = ozz::make_range(m_results.back());
		m_layers.emplace_back(layer);
	}

	inline void 
	_fix_root_translation(bindpose_soa& bp_soa) {
		size_t n = (size_t)m_ske->num_joints();
		const auto& parents = m_ske->joint_parents();
		for (size_t i = 0; i < n; ++i) {
			if (parents[i] == ozz::animation::Skeleton::kNoParent) {
				auto& trans = bp_soa[i / 4];
				const auto newtrans = ozz::math::simd_float4::zero();
				trans.translation.x = ozz::math::SetI(trans.translation.x, newtrans, 0);
				trans.translation.z = ozz::math::SetI(trans.translation.z, newtrans, 0);
				return;
			}
		}
	}

	int setup(lua_State* L) {
		const auto hie = (hierarchy_build_data*)luaL_checkudata(L, 2, "HIERARCHY_BUILD_DATA");
		const bool fr = lua_isnoneornil(L, 3) ? true : lua_toboolean(L, 3);
		if (m_ske){
			if (m_ske != hie->skeleton){
				return luaL_error(L, "using sample pose_result but different skeleton");
			}

			if (m_fix_root != fr){
				return luaL_error(L, "setup animiation step with different fix root argument, input:%s, cache:%s", (fr ? "true" : "false"), (m_fix_root ? "true" : "false"));
			}
		} else {
			m_ske = hie->skeleton;
			m_fix_root = fr;
		}
		return 0;
	}

	int do_sample(lua_State* L) {
		ozzSamplingCache* sampling = ozzSamplingCache::get(L, 2);
		ozzAnimation* animation = ozzAnimation::get(L, 3);
		float ratio = (float)luaL_checknumber(L, 4);
		float weight = (float)luaL_optnumber(L, 5, 1.0f);

		bindpose_soa bp_soa(m_ske->num_soa_joints());
		ozz::animation::SamplingJob job;
		if (m_ske->num_joints() > sampling->v->max_tracks()){
			sampling->v->Resize(m_ske->num_joints());
		}
		job.animation = animation->v;
		job.cache = sampling->v;
		job.ratio = ratio;
		job.output = ozz::make_range(bp_soa);
		if (!job.Run()) {
			return luaL_error(L, "sampling animation failed!");
		}
		_push_pose(bp_soa, weight);
		return 0;
	}
	int do_blend(lua_State* L) {
		const char* blendtype = luaL_checkstring(L, 2);
		lua_Integer n = luaL_checkinteger(L, 3);
		float weight = (float)luaL_optnumber(L, 4, 1.0f);
		float threshold = (float)luaL_optnumber(L, 5, 0.1f);
		size_t max = m_layers.size();
		if (n <= 0 || (size_t)n > max) {
			return luaL_error(L, "invalid blend range: %d", n);
		}
		if (n == 1) {
			m_layers.back().weight = weight;
			return 0;
		}
		ozz::animation::BlendingJob job;
		bindpose_soa bp_soa(m_ske->num_soa_joints());
		if (strcmp(blendtype, "blend") == 0) {
			job.layers = ozz::Range(&(m_layers[max-n]), n);
		} else if (strcmp(blendtype, "additive") == 0) {
			job.additive_layers = ozz::Range(&(m_layers[max-n]), n);
		} else {
			return luaL_error(L, "invalid blend type: %s", blendtype);
		}
		job.bind_pose = m_ske->joint_bind_poses();
		job.threshold = threshold;
		job.output = ozz::make_range(bp_soa);
		if (!job.Run()) {
			return luaL_error(L, "blend failed");
		}
		m_results.resize(max-n);
		m_layers.resize(max-n);
		_push_pose(bp_soa, weight);
		return 0;
	}

	int do_ik(lua_State* L) {
		if (!::do_ik(L, m_ske, m_results.back(), *this)){
			luaL_error(L, "do_ik failed!");
		}
		return 0;
	}

	int fetch_result(lua_State* L) {
		if (m_results.empty()) {
			return luaL_error(L, "no result");
		}
		if (m_fix_root) {
			_fix_root_translation(m_results.back());
		}
		ozz::animation::LocalToModelJob job;
		job.input = ozz::make_range(m_results.back());
		job.skeleton = m_ske;
		job.output = ozz::make_range(*(bindpose*)this);
		if (!job.Run()) {
			return luaL_error(L, "doing blend result to ltm job failed!");
		}
		return 0;
	}

	int clear(lua_State *L){
		m_ske = nullptr;
		m_results.clear();
		m_layers.clear();
		return 0;
	}

#define STATIC_MEM_FUNC(_NAME)	static int l##_NAME(lua_State* L){ auto pr = ozzPoseResult::get(L, 1); return pr->_NAME(L); }
	STATIC_MEM_FUNC(setup);
	STATIC_MEM_FUNC(do_sample);
	STATIC_MEM_FUNC(do_blend);
	STATIC_MEM_FUNC(fetch_result);
	STATIC_MEM_FUNC(do_ik);
	STATIC_MEM_FUNC(clear);
#undef MEM_FUNC

public:
	static int registerPoseResultMetatable(lua_State* L) {
		luaL_Reg l[] = {
			{ "setup",		  	lsetup},
			{ "do_sample",	  	ldo_sample},
			{ "do_blend",	  	ldo_blend},
			{ "fetch_result", 	lfetch_result},
			{ "do_ik",		  	ldo_ik},
			{ "end_animation",	lclear},
			{ "clear",			lclear},
			{ "count", 			lcount},
			{ "joint", 			ljoint},
			{ nullptr, 			nullptr},
		};

		luaClassType::reigister_mt(L, l);
		lua_pop(L, 1);
		return 1;
	}
};
REGISTER_LUA_CLASS(ozzPoseResult)

template<typename DataType>
struct vertex_data {
	struct data_stride {
		typedef DataType Type;
		DataType* data;
		uint32_t offset;
		uint32_t stride;
	};

	data_stride positions;
	data_stride normals;
	data_stride tangents;
};

struct in_vertex_data : public vertex_data<const void> {
	data_stride joint_weights;
	data_stride joint_indices;
};

typedef vertex_data<void> out_vertex_data;

template <typename DataStride>
static void
read_data_stride(lua_State *L, const char* name, int index, DataStride &ds){
	const int type = lua_getfield(L, index, name);
	if (type != LUA_TNIL)
	{
		lua_geti(L, -1, 1);
		const int type = lua_type(L, -1);
		switch (type){
		case LUA_TSTRING: ds.data = (typename DataStride::Type*)lua_tostring(L, -1); break;
		case LUA_TLIGHTUSERDATA:
		case LUA_TUSERDATA: ds.data = (typename DataStride::Type*)lua_touserdata(L, -1); break;
		default:
			luaL_error(L, "not support data type in data stride, only string and userdata is support, type:%d", type);
			return;
		}
		lua_pop(L, 1);

		lua_geti(L, -1, 2);
		ds.offset = (uint32_t)lua_tointeger(L, -1) - 1;
		lua_pop(L, 1);

		lua_geti(L, -1, 3);
		ds.stride = (uint32_t)lua_tointeger(L, -1);
		lua_pop(L, 1);
	}
	lua_pop(L, 1);
}

template<typename DataType>
static void
read_vertex_data(lua_State* L, int index, vertex_data<DataType>& vd) {
	read_data_stride(L, "POSITION", index, vd.positions);
	read_data_stride(L, "NORMAL", index, vd.normals);
	read_data_stride(L, "TANGENT", index, vd.tangents);
}

static void
read_in_vertex_data(lua_State *L, int index, in_vertex_data &vd){
	read_vertex_data(L, index, vd);
	read_data_stride(L, "WEIGHT", index, vd.joint_weights);
	read_data_stride(L, "INDICES", index, vd.joint_indices);
}

template<typename T, typename DataT>
static void
fill_skinning_job_field(uint32_t num_vertices, const DataT &d, ozz::Range<T> &r, size_t &stride) {
	const uint8_t* begin_data = (const uint8_t*)d.data + d.offset;
	r.begin = (T*)(begin_data);
	r.end	= (T*)(begin_data + d.stride * num_vertices);
	stride = d.stride;
}

static void
build_skinning_matrices(bindpose* skinning_matrices,
	const bindpose* current_pose,
	const bindpose* inverse_bind_matrices,
	const ozzJointRemap *jarray){
	if (jarray){
		assert(jarray->joints.size() == inverse_bind_matrices->size());
		for (size_t ii = 0; ii < jarray->joints.size(); ++ii){
			(*skinning_matrices)[ii] = (*current_pose)[jarray->joints[ii]] * (*inverse_bind_matrices)[ii];
		}
	} else {
		assert(current_pose->size() == inverse_bind_matrices->size() && skinning_matrices->size() == current_pose->size());
		for (size_t ii = 0; ii < inverse_bind_matrices->size(); ++ii){
			(*skinning_matrices)[ii] = (*current_pose)[ii] * (*inverse_bind_matrices)[ii];
		}
	}
}

static int
lbuild_skinning_matrices(lua_State *L){
	auto skinning_matrices = ozzBindpose::getBP(L, 1);
	auto current_bind_pose = ozzBindpose::getBP(L, 2);
	auto inverse_bind_matrices = ozzBindpose::getBP(L, 3);
	const ozzJointRemap *jarray = lua_isnoneornil(L, 4) ? nullptr : ozzJointRemap::get(L, 4);
	if (skinning_matrices->size() < inverse_bind_matrices->size()){
		return luaL_error(L, "invalid skinning matrices and inverse bind matrices, skinning matrices must larger than inverse bind matrices");
	}
	build_skinning_matrices(skinning_matrices, current_bind_pose, inverse_bind_matrices, jarray);
	return 0;
}

static int
lmesh_skinning(lua_State *L){
	auto skinning_matrices = ozzPoseResult::getBP(L, 1);

	luaL_checktype(L, 2, LUA_TTABLE);
	in_vertex_data vd = {0};
	read_in_vertex_data(L, 2, vd);

	luaL_checktype(L, 3, LUA_TTABLE);
	out_vertex_data ovd = {0};
	read_vertex_data(L, 3, ovd);

	const uint32_t num_vertices = (uint32_t)luaL_checkinteger(L, 4);
	const uint32_t influences_count = (uint32_t)luaL_optinteger(L, 5, 4);

	ozz::geometry::SkinningJob skinning_job;
	skinning_job.vertex_count = num_vertices;
	skinning_job.influences_count = influences_count;
	skinning_job.joint_matrices = ozz::make_range(*skinning_matrices);
	
	assert(vd.positions.data && "skinning system must provide 'position' attribute");

	fill_skinning_job_field(num_vertices, vd.positions, skinning_job.in_positions, skinning_job.in_positions_stride);
	fill_skinning_job_field(num_vertices, ovd.positions, skinning_job.out_positions, skinning_job.out_positions_stride);

	if (vd.normals.data) {
		fill_skinning_job_field(num_vertices, vd.normals, skinning_job.in_normals, skinning_job.in_normals_stride);
	}

	if (ovd.normals.data) {
		fill_skinning_job_field(num_vertices, ovd.normals, skinning_job.out_normals, skinning_job.out_normals_stride);
	}
	
	if (vd.tangents.data) {
		fill_skinning_job_field(num_vertices, vd.tangents, skinning_job.in_tangents, skinning_job.in_tangents_stride);
	}

	if (ovd.tangents.data) {
		fill_skinning_job_field(num_vertices, ovd.tangents, skinning_job.out_tangents, skinning_job.out_tangents_stride);
	}

	if (influences_count > 1) {
		assert(vd.joint_weights.data && "joint weight data is not valid!");
		fill_skinning_job_field(num_vertices, vd.joint_weights, skinning_job.joint_weights, skinning_job.joint_weights_stride);
	}
		
	assert(vd.joint_indices.data && "skinning job must provide 'indices' attribute");
	fill_skinning_job_field(num_vertices, vd.joint_indices, skinning_job.joint_indices, skinning_job.joint_indices_stride);

	if (!skinning_job.Run()) {
		luaL_error(L, "running skinning failed!");
	}

	return 0;
}

extern "C" {
LUAMOD_API int
luaopen_hierarchy_animation(lua_State *L) {
	ozzBindpose::registerBindposeMetatable(L);
	ozzPoseResult::registerPoseResultMetatable(L);
	lua_newtable(L);
	luaL_Reg l[] = {
		{ "mesh_skinning",				lmesh_skinning},
		{ "build_skinning_matrices",	lbuild_skinning_matrices},
		{ "new_animation",				ozzAnimation::create},
		{ "new_sampling_cache",			ozzSamplingCache::create},
		{ "new_bind_pose",				ozzBindpose::create},
		{ "bind_pose_mt",				ozzBindpose::getMT},
		{ "new_pose_result",			ozzPoseResult::create},
		{ "pose_result_mt",				ozzPoseResult::getMT},
		{ "new_aligned_memory",			ozzAllocator::create},
		{ "new_joint_remap",			ozzJointRemap::create},
		{ NULL, NULL },
	};
	luaL_setfuncs(L,l,0);
	return 1;
}

}
