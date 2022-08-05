#pragma once

#include <databinding/DataVariant.h>
#include <core/HtmlParser.h>
#include <core/ObserverPtr.h>
#include <databinding/DataView.h>
#include <databinding/DataExpression.h>
#include <memory>

namespace Rml {

class Text;
class Element;
class DataExpression;
using DataExpressionPtr = std::unique_ptr<DataExpression>;

class DataViewStyle final : public DataView {
public:
	DataViewStyle(Element* element, const std::string& modifier);
	bool Initialize(DataModel& model, const std::string& expression);
	std::vector<std::string> GetVariableNameList() const override;
	bool IsValid() const override;
	bool Update(DataModel& model) override;
private:
	ObserverPtr<Element> element;
	std::string modifier;
	DataExpressionPtr expression;
	Variant lastvalue = std::monostate {};
};

class DataViewAttr final : public DataView {
public:
	DataViewAttr(Element* element, const std::string& modifier);
	bool Initialize(DataModel& model, const std::string& expression);
	std::vector<std::string> GetVariableNameList() const override;
	bool IsValid() const override;
	bool Update(DataModel& model) override;
private:
	ObserverPtr<Element> element;
	std::string modifier;
	DataExpressionPtr expression;
};

class DataViewIf final : public DataView {
public:
	DataViewIf(Element* element);
	bool Initialize(DataModel& model, const std::string& expression);
	std::vector<std::string> GetVariableNameList() const override;
	bool IsValid() const override;
	bool Update(DataModel& model) override;
private:
	ObserverPtr<Element> element;
	DataExpressionPtr expression;
};

class DataViewFor final : public DataView {
public:
	DataViewFor(Element* element);
	bool Initialize(DataModel& model, const std::string& expression);
	bool Update(DataModel& model) override;
	std::vector<std::string> GetVariableNameList() const override;
	bool IsValid() const override;

private:
	ObserverPtr<Element> element;
	DataAddress container_address;
	std::string iterator_name;
	std::string iterator_index_name;
	size_t num_elements = 0;
};

class DataViewText final : public DataView {
public:
	DataViewText(Text* element);
	bool Initialize(DataModel& model);
	bool Update(DataModel& model) override;
	std::vector<std::string> GetVariableNameList() const override;
	bool IsValid() const override;

private:
	std::string BuildText() const;
	struct DataEntry {
		size_t index = 0; // Index into 'text'
		DataExpressionPtr data_expression;
		std::string value;
	};
	ObserverPtr<Text> element;
	std::string text;
	std::vector<DataEntry> data_entries;
};

}
