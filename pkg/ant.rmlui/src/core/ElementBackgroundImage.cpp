#include <core/ElementBackground.h>
#include <core/Texture.h>
#include <core/Element.h>
#include <core/Geometry.h>
#include <core/Document.h>
#include <core/Interface.h>
#include <core/Core.h>
#include <regex>

namespace Rml {

static void GetRectArray(float ratiow,float ratioh, Rect& rect, std::vector<Rect> &rect_array, float ox = 0, float oy = 0){
		float x = rect.origin.x;
		float y = rect.origin.y;
		float w = rect.size.w;
		float h = rect.size.h;
		float w1 = ratiow * w;
		float w2 = (1 - ratiow) * w;
		float w3 = (1 - 2 * ratiow) * w;
		float h1 = ratioh * h;
		float h2 = (1 - ratioh) * h;
		float h3 = (1 - 2 * ratioh) * h;
		rect_array[0] = Rect{float(x + ox), float(y + oy), w1, h1};
		rect_array[1] = Rect{float(w1 + ox), float(y + oy), w3, h1};
		rect_array[2] = Rect{float(w2 + ox), float(y + oy), w1, h1};
		rect_array[3] = Rect{float(x + ox), float(h1 + oy), w1, h3};
		rect_array[4] = Rect{float(w1 + ox), float(h1 + oy), w3, h3};
		rect_array[5] = Rect{float(w2 + ox), float(h1 + oy), w1, h3};
		rect_array[6] = Rect{float(x + ox), float(h2 + oy), w1, h1};
		rect_array[7] = Rect{float(w1 + ox), float(h2 + oy), w3, h1};
		rect_array[8] = Rect{float(w2 + ox), float(h2 + oy), w1, h1};
}

bool ElementBackground::GenerateImageGeometry(Element* element, Geometry& geometry, Box const& edge) {
	auto image = element->GetComputedProperty(PropertyId::BackgroundImage);
	if (!image->Has<std::string>()) {
		// "none"
		return false;
	}
	std::string path = image->Get<std::string>();
	if (path.empty()) {
		return false;
	}
	const auto& bounds = element->GetBounds();
	const auto& border = element->GetBorder();
	const auto& padding = element->GetPadding();

	Style::BoxType origin = element->GetComputedProperty(PropertyId::BackgroundOrigin)->Get<Style::BoxType>();

	Rect surface = Rect{ {0, 0}, bounds.size };
	if (surface.size.IsEmpty()) {
		return false;
	}

	switch (origin) {
	case Style::BoxType::PaddingBox:
		surface = surface - border;
		break;
	case Style::BoxType::BorderBox:
		break;
	case Style::BoxType::ContentBox:
		surface = surface - border - padding;
		break;
	}
	if (surface.size.IsEmpty()) {
		return false;
	}

	SamplerFlag repeat = element->GetComputedProperty(PropertyId::BackgroundRepeat)->Get<SamplerFlag>();
	Style::BackgroundSize backgroundSize = element->GetComputedProperty(PropertyId::BackgroundSize)->Get<Style::BackgroundSize>();
	Size texSize {
		element->GetComputedProperty(PropertyId::BackgroundSizeX)->Get<PropertyFloat>().ComputeW(element),
		element->GetComputedProperty(PropertyId::BackgroundSizeY)->Get<PropertyFloat>().ComputeH(element)
	};
	Point texPosition {
		element->GetComputedProperty(PropertyId::BackgroundPositionX)->Get<PropertyFloat>().ComputeW(element),
		element->GetComputedProperty(PropertyId::BackgroundPositionY)->Get<PropertyFloat>().ComputeH(element)
	};

	Color color = Color::FromSRGB(255, 255, 255, 255);
	color.ApplyOpacity(element->GetOpacity());
	if (!color.IsVisible())
		return false;

	bool isRT = false;
	if (regex_match(path, std::regex("<.*>"))) {
		isRT = true;
		path = regex_replace(path, std::regex("[<>]"), std::string(""));
	}
	auto const& texture = isRT? Texture::Fetch(element, path, surface.size): Texture::Fetch(element, path);
	if (!texture) {
		return false;
	}

	if (texSize.IsEmpty()) {
		texSize = texture.dimensions;
	}
	Size scale{
		surface.size.w / texSize.w,
		surface.size.h / texSize.h
	};
	Rect uv { {
		texPosition.x / texSize.w,
		texPosition.y / texSize.h
	}, {} };
	float aspectRatio = scale.w / scale.h;
	//uv
	switch (backgroundSize) {
	case Style::BackgroundSize::Auto:
		uv.size.w = scale.w;
		uv.size.h = scale.h;
		break;
	case Style::BackgroundSize::Contain:
		if (aspectRatio < 1.f) {
			uv.size.w = 1.f;
			uv.size.h = 1.f / aspectRatio;
		}
		else {
			uv.size.w = aspectRatio;
			uv.size.h = 1.f;
		}
		break;
	case Style::BackgroundSize::Cover:
		if (aspectRatio > 1.f) {
			uv.size.w = 1.f;
			uv.size.h = 1.f / aspectRatio;
		}
		else {
			uv.size.w = aspectRatio;
			uv.size.h = 1.f;
		}
		break;
	}
	Rml::MaterialHandle material;
	material = GetRenderInterface()->CreateTextureMaterial(texture.handle, repeat);
	geometry.SetMaterial(material);
	auto lattice_x = element->GetComputedProperty(PropertyId::BackgroundLatticeX)->Get<PropertyFloat>().value / 100.0f;
	auto lattice_y = element->GetComputedProperty(PropertyId::BackgroundLatticeY)->Get<PropertyFloat>().value / 100.0f;
	bool has_lattice = lattice_x > 0;

	if (paddingEdge.size() == 0 
		|| (origin == Style::BoxType::ContentBox && padding != EdgeInsets<float>{})
	) 
	{
		if(has_lattice){return false;}
		geometry.AddRectFilled(surface, color);
		geometry.UpdateUV(4, surface, uv);
	}
	else {
		if(has_lattice){
			if(lattice_y <= 0){
				lattice_y = lattice_x;
			}
			std::vector<Rect> surface_array(9);
			std::vector<Rect> uv_array(9);
			float ratiow = lattice_x;
			float ratioh = lattice_y * surface.size.w / surface.size.h;
			GetRectArray(ratiow, ratioh, surface, surface_array);
			float ratiou = (texture.dimensions.w - 2.f) / texture.dimensions.w * 0.5f;
			float ratiov = (texture.dimensions.h - 2.f) / texture.dimensions.h * 0.5f;
			GetRectArray(ratiou, ratiov, uv, uv_array);
			for(int idx = 0; idx < 9; ++idx){
				geometry.AddRectFilled(surface_array[idx], color);
				geometry.UpdateUV(4, surface_array[idx], uv_array[idx]);
			}		
		}
		else{
			geometry.AddPolygon(paddingEdge, color);
			geometry.UpdateUV(paddingEdge.size(), surface, uv);
		}	
	}
	geometry.UpdateVertices();
	return true;
}

}
