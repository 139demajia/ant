#pragma once

#include <core/ID.h>
#include <css/PropertyVector.h>
#include <css/StyleCache.h>
#include <core/AnimationKey.h>
#include <unordered_map>
#include <vector>

namespace Rml {

class Element;
class StyleSheetNode;
class Stream;

struct Keyframes {
	std::map<PropertyId, std::vector<AnimationKey>> properties;
};

class StyleSheet {
public:
	StyleSheet();
	~StyleSheet();
	StyleSheet(const StyleSheet&) = delete;
	StyleSheet& operator=(const StyleSheet&) = delete;
	void Merge(const StyleSheet& sheet);
	void AddNode(StyleSheetNode && node);
	void AddKeyframe(const std::string& identifier, const std::vector<float>& rule_values, const PropertyVector& properties);
	void Sort();
	const Keyframes* GetKeyframes(const std::string& name) const;
	Style::Combination GetElementDefinition(const Element* element) const;

private:
	std::vector<StyleSheetNode> stylenode;
	std::unordered_map<std::string, Keyframes> keyframes;
};

}
