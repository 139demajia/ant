#include <core/Texture.h>
#include <core/Interface.h>
#include <core/Core.h>
#include <core/Log.h>
#include <unordered_map>

namespace Rml {

Texture::Texture(const std::string& _source)
	: source(_source) {
	auto data = GetRenderInterface()->CreateTexture(source);
	if (!data) {
		Log::Message(Log::Level::Warning, "Failed to load texture from %s.", source.c_str());
		return;
	}
	handle = data->handle;
	dimensions = data->dimensions;
}

Texture::~Texture() {
	if (handle && GetRenderInterface()) {
		GetRenderInterface()->ReleaseTexture(handle);
		handle = 0;
	}
}

TextureHandle Texture::GetHandle() const {
	return handle;
}

const Size& Texture::GetDimensions() const {
	return dimensions;
}

using TextureMap = std::unordered_map<std::string, SharedPtr<Texture>>;
static TextureMap textures;

void Texture::Shutdown() {
#if !defined NDEBUG
	// All textures not owned by the database should have been released at this point.
	int num_leaks_file = 0;
	for (auto& texture : textures) {
		num_leaks_file += (texture.second.use_count() > 1);
	}
	if (num_leaks_file > 0) {
		Log::Message(Log::Level::Error, "Textures leaked during shutdown. Total: %d.", num_leaks_file);
	}
#endif
	textures.clear();
}

SharedPtr<Texture> Texture::Fetch(const std::string& path) {
	auto iterator = textures.find(path);
	if (iterator != textures.end()) {
		return iterator->second;
	}
	auto resource = MakeShared<Texture>(path);
	textures[path] = resource;
	return resource;
}

}
