#include <core/ElementBackground.h>
#include <core/Texture.h>
#include <core/Element.h>
#include <core/Geometry.h>
#include <core/Document.h>
#include <core/Interface.h>
#include <core/Core.h>
#include <regex>

namespace Rml {

static void GetRectArray(float wl, float wr, float ht, float hb, Rect& rect, std::vector<Rect> &rect_array){
		float x = rect.origin.x;
		float y = rect.origin.y;
		float w = rect.size.w;
		float h = rect.size.h;
		float w1 = wl * w;
		float w2 = (1 - wl - wr) * w;
		float w3 = wr * w;
		float w4 = (1 - wr) * w;
		float h1 = ht * h;
		float h2 = (1 - ht - hb) * h;
		float h3 = hb * h;
		float h4 = (1 - hb) * h;
		rect_array[0] = Rect{x     , y     , w1, h1};
		rect_array[1] = Rect{x + w1, y     , w2, h1};
		rect_array[2] = Rect{x + w4, y     , w3, h1};
		rect_array[3] = Rect{x     , y + h1, w1, h2};
		rect_array[4] = Rect{x + w1, y + h1, w2, h2};
		rect_array[5] = Rect{x + w4, y + h1, w3, h2};
		rect_array[6] = Rect{x     , y + h4, w1, h3};
		rect_array[7] = Rect{x + w1, y + h4, w2, h3};
		rect_array[8] = Rect{x + w4, y + h4, w3, h3};
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
	Material* material = GetRenderInterface()->CreateTextureMaterial(texture.handle, repeat);
	geometry.SetMaterial(material);
	auto lattice_x1 = element->GetComputedProperty(PropertyId::BackgroundLatticeX1)->Get<PropertyFloat>().value / 100.0f;
	bool has_lattice = lattice_x1 > 0;

	if (edge.padding.size() == 0 
		|| (origin == Style::BoxType::ContentBox && padding != EdgeInsets<float>{})
	) 
	{
		if(has_lattice){return false;}
		geometry.AddRectFilled(surface, color);
		geometry.UpdateUV(4, surface, uv);
	}
	else {
		if(has_lattice){
			auto lattice_y1 = element->GetComputedProperty(PropertyId::BackgroundLatticeY1)->Get<PropertyFloat>().value / 100.0f;
			auto lattice_x2 = element->GetComputedProperty(PropertyId::BackgroundLatticeX2)->Get<PropertyFloat>().value / 100.0f;
			auto lattice_y2 = element->GetComputedProperty(PropertyId::BackgroundLatticeY2)->Get<PropertyFloat>().value / 100.0f;
			if(lattice_y1 <= 0){lattice_y1 = lattice_x1;}
			if(lattice_x2 <= 0){lattice_x2 = lattice_x1;}
			if(lattice_y2 <= 0){lattice_y2 = lattice_y1;}
			std::vector<Rect> surface_array(9);
			std::vector<Rect> uv_array(9);
			GetRectArray(lattice_x1, lattice_y1, lattice_x2, lattice_y2, surface, surface_array);
			float uw = (texture.dimensions.w - 2.f) / texture.dimensions.w * 0.5f;
			float vh = (texture.dimensions.h - 2.f) / texture.dimensions.h * 0.5f;
			GetRectArray(uw, uw, vh, vh, uv, uv_array);
			for(int idx = 0; idx < 9; ++idx){
				geometry.AddRectFilled(surface_array[idx], color);
				geometry.UpdateUV(4, surface_array[idx], uv_array[idx]);
			}		
		}
		else{
			geometry.AddPolygon(edge.padding, color);
			geometry.UpdateUV(edge.padding.size(), surface, uv);
		}	
	}
<<<<<<< HEAD
	geometry.UpdateVertices();
=======
	if (element->IsGray()) {
		geometry.SetGray();
	}
>>>>>>> 8b8b73d75 (rework filter:gray)
	return true;
}

}
