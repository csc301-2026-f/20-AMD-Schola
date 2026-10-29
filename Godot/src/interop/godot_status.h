// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"

#include <godot_cpp/classes/global_constants.hpp>
#include <godot_cpp/variant/string.hpp>

#include <string>

inline godot::Error to_godot_error(const schola::Status &p_status) {
	switch (p_status.get_code()) {
		case schola::StatusCode::OK:
			return godot::OK;
		case schola::StatusCode::INVALID_ARGUMENT:
			return godot::ERR_INVALID_PARAMETER;
		case schola::StatusCode::NOT_FOUND:
			return godot::ERR_DOES_NOT_EXIST;
		case schola::StatusCode::INVALID_DATA:
		case schola::StatusCode::INCOMPATIBLE:
			return godot::ERR_INVALID_DATA;
		case schola::StatusCode::FAILED_PRECONDITION:
			return godot::ERR_UNCONFIGURED;
		case schola::StatusCode::TIMEOUT:
			return godot::ERR_TIMEOUT;
		case schola::StatusCode::CLOSED:
			return godot::ERR_CONNECTION_ERROR;
		default:
			return godot::FAILED;
	}
}

inline godot::String to_godot_string(const std::string &p_text) {
	return godot::String::utf8(p_text.c_str());
}
