#pragma once

#include <string>
#include <utility>

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
	static Status ok() { return Status(StatusCode::OK, std::string()); }
	static Status error(StatusCode p_code, std::string p_message) {return Status(p_code, std::move(p_message)); }
	bool is_ok() const { return code == StatusCode::OK; }
	StatusCode get_code() const { return code; }
	const std::string &get_message() const { return message; }

private:
	Status(StatusCode p_code, std::string p_message):code(p_code), message(std::move(p_message)) {}
	StatusCode code;
	std::string message;
};

}
