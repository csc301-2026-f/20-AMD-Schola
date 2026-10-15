// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include <string>

namespace schola {

enum class StatusCode {
	OK,
	INVALID_ARGUMENT,
	NOT_FOUND,
	INVALID_DATA,
	INCOMPATIBLE,
	FAILED_PRECONDITION,
	TIMEOUT,
	CLOSED,
	RUNTIME_FAILURE,
};

class [[nodiscard]] Status {
public:
	static Status ok();
	static Status error(StatusCode p_code, std::string p_message);

	bool is_ok() const;
	StatusCode get_code() const;
	const std::string &get_message() const;

private:
	Status(StatusCode p_code, std::string p_message);

	StatusCode code;
	std::string message;
};

} // namespace schola
