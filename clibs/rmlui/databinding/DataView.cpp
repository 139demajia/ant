#include <databinding/DataView.h>
#include <databinding/DataModel.h>
#include <core/Document.h>
#include <core/Element.h>
#include <core/Text.h>
#include <core/Log.h>
#include <core/StringUtilities.h>

namespace Rml {

static int GetNodeDepth(Node* e) {
	int depth = 0;
	for (Element* parent = e->GetParentNode(); parent; parent = parent->GetParentNode()) {
		depth++;
	}
	return depth;
}

DataView::DataView(Node* node)
	: depth(GetNodeDepth(node))
{ }

int DataView::GetDepth() const {
	return depth;
}

DataViewStyle::DataViewStyle(Element* element, const std::string& modifier)
	: DataView(element)
	, element(element->GetObserverPtr())
	, modifier(modifier)
{}

bool DataViewStyle::Initialize(DataModel& model, const std::string& expression_str) {
	expression = std::make_unique<DataExpression>();
	DataExpressionInterface expr_interface(&model, element.get());
	bool result = expression->Parse(expr_interface, expression_str, false);
	return result;
}

std::vector<std::string> DataViewStyle::GetVariableNameList() const {
	assert(expression);
	return expression->GetVariableNameList();
}

bool DataViewStyle::IsValid() const {
	return element && !element->IsRemoved();
}

bool DataViewStyle::Update(DataModel& model) {
	const std::string& property_name = modifier;
	bool result = false;
	DataVariant value;
	DataExpressionInterface expr_interface(&model, element.get());
	if (element && expression->Run(expr_interface, value)) {
		if (lastvalue != value) {
			lastvalue = value;
			element->SetProperty(property_name, VariantHelper::ToStringOpt(value));
			result = true;
		}
	}
	return result;
}


DataViewAttr::DataViewAttr(Element* element, const std::string& modifier)
	: DataView(element)
	, element(element->GetObserverPtr())
	, modifier(modifier)
{}

bool DataViewAttr::Initialize(DataModel& model, const std::string& expression_str) {
	expression = std::make_unique<DataExpression>();
	DataExpressionInterface expr_interface(&model, element.get());
	bool result = expression->Parse(expr_interface, expression_str, false);
	return result;
}

std::vector<std::string> DataViewAttr::GetVariableNameList() const {
	assert(expression);
	return expression->GetVariableNameList();
}

bool DataViewAttr::IsValid() const {
	return element && !element->IsRemoved();
}

bool DataViewAttr::Update(DataModel& model) {
	const std::string& property_name = modifier;
	bool result = false;
	DataVariant variant;
	DataExpressionInterface expr_interface(&model, element.get());

	if (element && expression->Run(expr_interface, variant)) {
		auto newValue = VariantHelper::ToStringOpt(variant);
		auto oldValue = element->GetAttribute(property_name);
		if (!oldValue || *newValue != *oldValue) {
			element->SetAttribute(property_name, *newValue);
			result = true;
		}
	}
	return result;
}

DataViewIf::DataViewIf(Element* element)
	: DataView(element)
	, element(element->GetObserverPtr())
{}

bool DataViewIf::Initialize(DataModel& model, const std::string& expression_str) {
	expression = std::make_unique<DataExpression>();
	DataExpressionInterface expr_interface(&model, element.get());
	bool result = expression->Parse(expr_interface, expression_str, false);
	return result;
}

std::vector<std::string> DataViewIf::GetVariableNameList() const {
	assert(expression);
	return expression->GetVariableNameList();
}

bool DataViewIf::IsValid() const {
	return element && !element->IsRemoved();
}

bool DataViewIf::Update(DataModel& model) {
	bool result = false;
	DataVariant variant;
	DataExpressionInterface expr_interface(&model, element.get());

	if (element && expression->Run(expr_interface, variant))
	{
		const bool value = VariantHelper::Get<bool>(variant);
		// fixed nested data-if for same variant bug
		//if (element->IsVisible() != value) {
			element->SetVisible(value);
			result = true;
		//}
	}
	return result;
}

DataViewFor::DataViewFor(Element* element)
	: DataView(element)
	, element(element->GetObserverPtr())
{}

bool DataViewFor::Initialize(DataModel& model, const std::string& in_expression) {
	std::vector<std::string> iterator_container_pair;
	StringUtilities::ExpandString(iterator_container_pair, in_expression, ':');

	if (iterator_container_pair.empty() || iterator_container_pair.size() > 2 || iterator_container_pair.front().empty() || iterator_container_pair.back().empty()) {
		Log::Message(Log::Level::Warning, "Invalid syntax in data-for '%s'", in_expression.c_str());
		return false;
	}

	if (iterator_container_pair.size() == 2) {
		std::vector<std::string> iterator_index_pair;
		StringUtilities::ExpandString(iterator_index_pair, iterator_container_pair.front(), ',');
		if (iterator_index_pair.empty()) {
			Log::Message(Log::Level::Warning, "Invalid syntax in data-for '%s'", in_expression.c_str());
			return false;
		}
		else if (iterator_index_pair.size() == 1) {
			iterator_name = iterator_index_pair.front();
		}
		else if (iterator_index_pair.size() == 2) {
			iterator_name = iterator_index_pair.front();
			iterator_index_name = iterator_index_pair.back();
		}
	}

	if (iterator_name.empty())
		iterator_name = "it";
	if (iterator_index_name.empty())
		iterator_index_name = "it_index";
	const std::string& container_name = iterator_container_pair.back();
	container_address = model.ResolveAddress(container_name, element.get());
	if (container_address.empty())
		return false;
	element->SetVisible(false);
	element->RemoveAttribute("data-for");
	return true;
}

bool DataViewFor::Update(DataModel& model) {
	DataVariable variable = model.GetVariable(container_address);
	if (!variable)
		return false;

	size_t size = (size_t)variable.Size();

	for (size_t i = num_elements; i < size; ++i) {
		DataAddress iterator_address;
		iterator_address.reserve(container_address.size() + 1);
		iterator_address = container_address;
		iterator_address.push_back(DataAddressEntry((int)i));
		DataAddress iterator_index_address = {
			{"literal"}, {"int"}, {(int)i}
		};
		Node* sibling = element->Clone();
		model.InsertAlias(sibling, iterator_name, std::move(iterator_address));
		model.InsertAlias(sibling, iterator_index_name, std::move(iterator_index_address));
		model.MarkDirty();
		element->GetParentNode()->InsertBefore(sibling, element.get());
	}
	for (size_t i = size; i < num_elements; ++i) {
		Node* sibling = element->GetPreviousSibling();
		model.EraseAliases(sibling);
		model.MarkDirty();
		element->GetParentNode()->RemoveChild(sibling);
	}
	num_elements = size;
	return true;
}

std::vector<std::string> DataViewFor::GetVariableNameList() const {
	assert(!container_address.empty());
	return std::vector<std::string>{ container_address.front().name };
}

bool DataViewFor::IsValid() const {
	return element && !element->IsRemoved();
}

DataViewText::DataViewText(Text* element)
	: DataView(element)
	, element(element->GetObserverPtr())
{}

bool DataViewText::Initialize(DataModel& model) {
	if (!element->GetParentNode()->IsVisible()) {
		return false;
	}
	const std::string& in_text = element->GetText();
	text.reserve(in_text.size());
	DataExpressionInterface expression_interface(&model, element.get());

	size_t previous_close_brackets = 0;
	size_t begin_brackets = 0;
	while ((begin_brackets = in_text.find("{{", begin_brackets)) != std::string::npos) {
		text.insert(text.end(), in_text.begin() + previous_close_brackets, in_text.begin() + begin_brackets);

		const size_t begin_name = begin_brackets + 2;
		const size_t end_name = in_text.find("}}", begin_name);

		if (end_name == std::string::npos)
			return false;

		DataEntry entry;
		entry.index = text.size();
		entry.data_expression = std::make_unique<DataExpression>();
		std::string expression_str(in_text.begin() + begin_name, in_text.begin() + end_name);
		if (entry.data_expression->Parse(expression_interface, expression_str, false))
			data_entries.push_back(std::move(entry));

		previous_close_brackets = end_name + 2;
		begin_brackets = previous_close_brackets;
	}

	if (data_entries.empty())
		return false;

	if (previous_close_brackets < in_text.size())
		text.insert(text.end(), in_text.begin() + previous_close_brackets, in_text.end());

	return true;
}

bool DataViewText::Update(DataModel& model) {
	if (!element->GetParentNode()->IsVisible()) {
		return false;
	}
	bool entries_modified = false;
	{
		DataExpressionInterface expression_interface(&model, element.get());

		for (DataEntry& entry : data_entries) {
			assert(entry.data_expression);
			DataVariant variant;
			bool result = entry.data_expression->Run(expression_interface, variant);
			const std::string value = VariantHelper::ToString(variant);
			if (result && entry.value != value) {
				entry.value = value;
				entries_modified = true;
			}
		}
	}

	if (entries_modified) {
		if (Text* text_element = static_cast<Text*>(element.get())) {
			std::string new_text = BuildText();
			text_element->SetText(new_text);
		}
	}

	return entries_modified;
}

std::vector<std::string> DataViewText::GetVariableNameList() const {
	std::vector<std::string> full_list;
	full_list.reserve(data_entries.size());

	for (const DataEntry& entry : data_entries) {
		assert(entry.data_expression);

		std::vector<std::string> entry_list = entry.data_expression->GetVariableNameList();
		full_list.insert(full_list.end(),
			std::make_move_iterator(entry_list.begin()),
			std::make_move_iterator(entry_list.end())
		);
	}

	return full_list;
}

std::string DataViewText::BuildText() const {
	size_t reserve_size = text.size();

	for (const DataEntry& entry : data_entries)
		reserve_size += entry.value.size();

	std::string result;
	result.reserve(reserve_size);

	size_t previous_index = 0;
	for (const DataEntry& entry : data_entries) {
		result += text.substr(previous_index, entry.index - previous_index);
		result += entry.value;
		previous_index = entry.index;
	}

	if (previous_index < text.size())
		result += text.substr(previous_index);

	return result;
}

bool DataViewText::IsValid() const {
	return element && element->GetParentNode() && !element->GetParentNode()->IsRemoved();
}

}
