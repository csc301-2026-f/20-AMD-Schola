// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "core/common/status.h"

#include <cassert>
#include <utility>

namespace schola {

Status Status::ok() {
	return Status(StatusCode::OK, {});
}

Status Status::error(StatusCode p_code, std::string p_message) {
	assert(p_code != StatusCode::OK);
	assert(!p_message.empty());
	return Status(p_code, std::move(p_message));
}

bool Status::is_ok() const {
	return code == StatusCode::OK;
}

StatusCode Status::get_code() const {
	return code;
}

const std::string &Status::get_message() const {
	return message;
}

Status::Status(StatusCode p_code, std::string p_message) :
		code(p_code),
		message(std::move(p_message)) {
}

} // namespace schola
