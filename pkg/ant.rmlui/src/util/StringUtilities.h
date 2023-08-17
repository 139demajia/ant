#pragma once

#include <string>
#include <vector>

namespace Rml::StringUtilities {
	void ExpandString(std::vector<std::string>& string_list, const std::string& string, const char delimiter);
	void ExpandString2(std::vector<std::string>& string_list, const std::string& string, const char delimiter, char quote_character, char unquote_character, bool ignore_repeated_delimiters = false);

	std::string ToLower(const std::string& string);

	inline bool IsWhitespace(const char x) {
		return (x == '\r' || x == '\n' || x == ' ' || x == '\t' || x == '\f');
	}

	std::string StripWhitespace(const std::string& string);
}
