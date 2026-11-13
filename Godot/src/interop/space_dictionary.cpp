// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "interop/space_dictionary.h"

#include "core/common/status.h"
#include "core/spaces/space.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace schola {

namespace {

Status bad_space(const std::string &p_path, const std::string &p_message) {
	const std::string where = p_path.empty() ? "space" : "space '" + p_path + "'";
	return Status::error(StatusCode::INVALID_DATA, where + ": " + p_message);
}

std::string child_path(const std::string &p_path, const std::string &p_key) {
	return p_path.empty() ? p_key : p_path + "." + p_key;
}

bool is_text(const godot::Variant &p_value) {
	return p_value.get_type() == godot::Variant::STRING || p_value.get_type() == godot::Variant::STRING_NAME;
}

std::string to_std_string(const godot::Variant &p_value) {
	return godot::String(p_value).utf8().get_data();
}

// Only an int that fits in 32 bits; floats are rejected rather than truncated.
bool read_int32(const godot::Variant &p_value, int32_t &r_value) {
	if (p_value.get_type() != godot::Variant::INT) {
		return false;
	}
	const int64_t value = p_value;
	if (value < std::numeric_limits<int32_t>::min() || value > std::numeric_limits<int32_t>::max()) {
		return false;
	}
	r_value = static_cast<int32_t>(value);
	return true;
}

Status read_int32_array(const godot::Dictionary &p_dictionary, const char *p_field, const std::string &p_path,
		std::vector<int32_t> &r_values) {
	const godot::Variant value = p_dictionary.get(p_field, godot::Variant());
	if (value.get_type() != godot::Variant::ARRAY) {
		return bad_space(p_path, std::string(p_field) + " must be an Array of ints");
	}
	const godot::Array array = value;
	std::vector<int32_t> values;
	values.reserve(array.size());
	for (int64_t index = 0; index < array.size(); ++index) {
		int32_t item = 0;
		if (!read_int32(array[index], item)) {
			return bad_space(p_path, std::string(p_field) + "[" + std::to_string(index) + "] must be a 32-bit int");
		}
		values.push_back(item);
	}
	r_values = std::move(values);
	return Status::ok();
}

// space_to_dictionary() writes an unbounded side as null; p_unbounded restores it.
Status read_bounds(const godot::Dictionary &p_dictionary, const char *p_field, float p_unbounded,
		const std::string &p_path, std::vector<float> &r_values) {
	const godot::Variant value = p_dictionary.get(p_field, godot::Variant());
	if (value.get_type() != godot::Variant::ARRAY) {
		return bad_space(p_path, std::string(p_field) + " must be an Array of numbers or nulls");
	}
	const godot::Array array = value;
	std::vector<float> values;
	values.reserve(array.size());
	for (int64_t index = 0; index < array.size(); ++index) {
		const godot::Variant bound = array[index];
		if (bound.get_type() == godot::Variant::NIL) {
			values.push_back(p_unbounded);
		} else if (bound.get_type() == godot::Variant::INT || bound.get_type() == godot::Variant::FLOAT) {
			values.push_back(static_cast<float>(static_cast<double>(bound)));
		} else {
			return bad_space(p_path, std::string(p_field) + "[" + std::to_string(index) + "] must be a number or null");
		}
	}
	r_values = std::move(values);
	return Status::ok();
}

Status read_dtype(const godot::Variant &p_value, const std::string &p_path, DType &r_dtype) {
	if (!is_text(p_value)) {
		return bad_space(p_path, "dtype must be a String");
	}
	const std::string name = to_std_string(p_value);
	for (int32_t index = 0; index <= static_cast<int32_t>(DType::BOOL); ++index) {
		const DType dtype = static_cast<DType>(index);
		if (name == dtype_name(dtype)) {
			r_dtype = dtype;
			return Status::ok();
		}
	}
	return bad_space(p_path, "unknown dtype '" + name + "'");
}

Status read_space(const godot::Variant &p_value, const std::string &p_path, Space &r_space) {
	if (p_value.get_type() != godot::Variant::DICTIONARY) {
		return bad_space(p_path, "must be a Dictionary");
	}
	const godot::Dictionary dictionary = p_value;
	const godot::Variant type_value = dictionary.get("type", godot::Variant());
	if (!is_text(type_value)) {
		return bad_space(p_path, "type must be a String");
	}
	const std::string type = to_std_string(type_value);

	if (type == "Box") {
		BoxSpace box;
		Status status = read_bounds(dictionary, "low", -std::numeric_limits<float>::infinity(), p_path, box.low);
		if (status.is_ok()) {
			status = read_bounds(dictionary, "high", std::numeric_limits<float>::infinity(), p_path, box.high);
		}
		if (status.is_ok()) {
			status = read_int32_array(dictionary, "shape", p_path, box.shape);
		}
		if (status.is_ok()) {
			status = read_dtype(dictionary.get("dtype", godot::Variant()), p_path, box.dtype);
		}
		if (!status.is_ok()) {
			return status;
		}
		r_space = Space(std::move(box));
	} else if (type == "Discrete" || type == "MultiBinary") {
		int32_t n = 0;
		if (!read_int32(dictionary.get("n", godot::Variant()), n)) {
			return bad_space(p_path, "n must be a 32-bit int");
		}
		r_space = type == "Discrete" ? Space(DiscreteSpace{ n }) : Space(MultiBinarySpace{ n });
	} else if (type == "MultiDiscrete") {
		MultiDiscreteSpace multi_discrete;
		const Status status = read_int32_array(dictionary, "nvec", p_path, multi_discrete.nvec);
		if (!status.is_ok()) {
			return status;
		}
		r_space = Space(std::move(multi_discrete));
	} else if (type == "Dict") {
		const godot::Variant spaces_value = dictionary.get("spaces", godot::Variant());
		if (spaces_value.get_type() != godot::Variant::DICTIONARY) {
			return bad_space(p_path, "spaces must be a Dictionary");
		}
		const godot::Dictionary spaces = spaces_value;
		const godot::Array keys = spaces.keys();
		DictSpace dict;
		for (int64_t index = 0; index < keys.size(); ++index) {
			const godot::Variant key = keys[index];
			if (!is_text(key)) {
				return bad_space(p_path, "Dict keys must be Strings");
			}
			const std::string name = to_std_string(key);
			Space entry;
			const Status status = read_space(spaces[key], child_path(p_path, name), entry);
			if (!status.is_ok()) {
				return status;
			}
			dict.entries.emplace_back(name, std::move(entry));
		}
		r_space = Space(std::move(dict));
	} else {
		return bad_space(p_path, "unknown type '" + type + "'");
	}
	return Status::ok();
}

godot::Array bounds_to_array(const std::vector<float> &p_bounds) {
	godot::Array result;
	for (float bound : p_bounds) {
		result.push_back(std::isinf(bound) ? godot::Variant() : godot::Variant(bound));
	}
	return result;
}

template <typename T>
godot::Array ints_to_array(const std::vector<T> &p_values) {
	godot::Array result;
	for (T value : p_values) {
		result.push_back(static_cast<int64_t>(value));
	}
	return result;
}

} //namespace

godot::Dictionary space_to_dictionary(const Space &p_space) {
	godot::Dictionary result;
	if (const BoxSpace *box = p_space.get_if<BoxSpace>()) {
		result["type"] = "Box";
		result["low"] = bounds_to_array(box->low);
		result["high"] = bounds_to_array(box->high);
		result["shape"] = ints_to_array(box->shape);
		result["dtype"] = dtype_name(box->dtype);
	} else if (const DiscreteSpace *discrete = p_space.get_if<DiscreteSpace>()) {
		result["type"] = "Discrete";
		result["n"] = discrete->n;
	} else if (const MultiDiscreteSpace *multi_discrete = p_space.get_if<MultiDiscreteSpace>()) {
		result["type"] = "MultiDiscrete";
		result["nvec"] = ints_to_array(multi_discrete->nvec);
	} else if (const MultiBinarySpace *multi_binary = p_space.get_if<MultiBinarySpace>()) {
		result["type"] = "MultiBinary";
		result["n"] = multi_binary->n;
	} else {
		godot::Dictionary spaces;
		for (const auto &entry : p_space.get_if<DictSpace>()->entries) {
			spaces[godot::String::utf8(entry.first.c_str())] = space_to_dictionary(entry.second);
		}
		result["type"] = "Dict";
		result["spaces"] = spaces;
	}
	return result;
}

Status dictionary_to_space(const godot::Variant &p_value, Space &r_space) {
	Space space;
	Status status = read_space(p_value, "", space);
	if (!status.is_ok()) {
		return status;
	}
	status = space.check_definition();
	if (!status.is_ok()) {
		return status;
	}
	r_space = std::move(space);
	return Status::ok();
}

} //namespace schola
