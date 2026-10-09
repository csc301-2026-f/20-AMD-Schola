// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include <string>
#include <utility>

namespace schola {

// Failure categories reported by space definition and point validation.
enum class SpaceValidationCode {
	OK,
	// A space definition is malformed, such as mismatched Box bounds or a non-positive Discrete size.
	INVALID_ARGUMENT,
	// A Dict point is missing a key that its space requires.
	NOT_FOUND,
	// A point value is outside the bounds allowed by its space.
	INVALID_DATA,
	// A point's kind or size does not match its space.
	INCOMPATIBLE,
};

// Recoverable result of a space check. This type is local to the spaces module and is not the
// project-wide error type described in the development contract.
class [[nodiscard]] SpaceValidationResult {
public:
	static SpaceValidationResult ok() { return SpaceValidationResult(SpaceValidationCode::OK, std::string()); }
	static SpaceValidationResult error(SpaceValidationCode p_code, std::string p_message) { return SpaceValidationResult(p_code, std::move(p_message)); }
	bool is_ok() const { return code == SpaceValidationCode::OK; }
	SpaceValidationCode get_code() const { return code; }
	// Describes what failed, including the Dict key path when the failure is nested.
	const std::string &get_message() const { return message; }

private:
	SpaceValidationResult(SpaceValidationCode p_code, std::string p_message) :
			code(p_code), message(std::move(p_message)) {}
	SpaceValidationCode code;
	std::string message;
};

} // namespace schola
