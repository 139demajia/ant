#pragma once

#include <core/Types.h>
#include <core/SharedPtr.h>
#include <core/Interface.h>
#include <memory>
#include <string>

namespace Rml {

struct Texture: public TextureData {
public:
	Texture(const std::string& path);
	~Texture();
	TextureHandle GetHandle() const;
	const Size& GetDimensions() const;
	static void Shutdown();
	static SharedPtr<Texture> Fetch(const std::string& path);
private:
	std::string source;
};

}
