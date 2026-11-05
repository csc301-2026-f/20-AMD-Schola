// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "interop/variant_conversion.h"

#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cmath>
#include <cstdint>
#include <limits>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace schola {

namespace {

constexpr int64_t INT32_LOW = std::numeric_limits<int32_t>::min();
constexpr int64_t INT32_HIGH = std::numeric_limits<int32_t>::max();

std::string type_name(const godot::Variant &p_value) {
	return godot::Variant::get_type_name(p_value.get_type()).utf8().get_data();
}

std::string to_std_string(const godot::String &p_value) {
	return p_value.utf8().get_data();
}

std::string at_path(const std::string &p_path, const std::string &p_message) {
	if (p_path.empty()) {
		return p_message;
	}
	return "at '" + p_path + "': " + p_message;
}

std::string join_path(const std::string &p_path, const std::string &p_key) {
	return p_path.empty() ? p_key : p_path + "." + p_key;
}

Status invalid(const std::string &p_path, const std::string &p_message) {
	return Status::error(StatusCode::INVALID_ARGUMENT, at_path(p_path, p_message));
}

bool is_string(const godot::Variant &p_value) {
	return p_value.get_type() == godot::Variant::STRING || p_value.get_type() == godot::Variant::STRING_NAME;
}

int64_t variant_size(const godot::Variant &p_value) {
	switch (p_value.get_type()) {
		case godot::Variant::ARRAY:
			return godot::Array(p_value).size();
		case godot::Variant::DICTIONARY:
			return godot::Dictionary(p_value).size();
		case godot::Variant::PACKED_BYTE_ARRAY:
			return godot::PackedByteArray(p_value).size();
		case godot::Variant::PACKED_INT32_ARRAY:
			return godot::PackedInt32Array(p_value).size();
		case godot::Variant::PACKED_FLOAT32_ARRAY:
			return godot::PackedFloat32Array(p_value).size();
		case godot::Variant::PACKED_FLOAT64_ARRAY:
			return godot::PackedFloat64Array(p_value).size();
		default:
			return -1;
	}
}

std::string short_description(const Space &p_space) {
	if (const BoxSpace *box = p_space.get_if<BoxSpace>()) {
		std::string shape;
		for (size_t i = 0; i < box->shape.size(); ++i) {
			shape += (i > 0 ? ", " : "") + std::to_string(box->shape[i]);
		}
		return "Box(shape=[" + shape + "])";
	}
	if (p_space.get_if<DictSpace>()) {
		return "Dict";
	}
	return p_space.to_string();
}

Status wrong_value(const std::string &p_path, const char *p_expected, int64_t p_expected_size, const Space &p_space, const godot::Variant &p_value) {
	std::string message = std::string("expected ") + p_expected;
	if (p_expected_size >= 0) {
		message += " of size " + std::to_string(p_expected_size);
	}
	message += " for " + short_description(p_space) + ", got " + type_name(p_value);
	const int64_t size = variant_size(p_value);
	if (size >= 0) {
		message += " of size " + std::to_string(size);
	}
	return invalid(p_path, message);
}

std::string narrowing_error(int64_t p_index, const std::string &p_value, bool p_whole, DType p_dtype) {
	const std::string prefix = "Box value at index " + std::to_string(p_index) + " is " + p_value;
	return p_whole ? prefix + ", which float32 cannot represent exactly" : prefix + " but dtype " + dtype_name(p_dtype) + " needs a whole number";
}

// Narrows to float32, the wire type. Integer and bool dtypes reject values that narrowing would change,
// because validate() only sees the float and would accept 1.00000001 as 1.
bool push_float(double p_value, int64_t p_index, DType p_dtype, std::vector<float> &r_values, std::string &r_error) {
	const float value = static_cast<float>(p_value);
	if (is_whole_dtype(p_dtype) && !std::isnan(p_value) && static_cast<double>(value) != p_value) {
		r_error = narrowing_error(p_index, to_std_string(godot::String::num(p_value)), std::floor(p_value) == p_value, p_dtype);
		return false;
	}
	r_values.push_back(value);
	return true;
}

// Like push_float, but compares against the int64_t itself, since a double rounds integers above 2^53.
bool push_int(int64_t p_value, int64_t p_index, DType p_dtype, std::vector<float> &r_values, std::string &r_error) {
	const float value = static_cast<float>(p_value);
	// 2^63 is the smallest float above INT64_MAX; casting it back to int64_t would overflow
	if (is_whole_dtype(p_dtype) && (value >= std::ldexp(1.0f, 63) || static_cast<int64_t>(value) != p_value)) {
		r_error = narrowing_error(p_index, std::to_string(p_value), true, p_dtype);
		return false;
	}
	r_values.push_back(value);
	return true;
}

// r_error names a bad element
bool read_floats(const godot::Variant &p_value, DType p_dtype, std::vector<float> &r_values, std::string &r_error) {
	r_values.clear();
	switch (p_value.get_type()) {
		case godot::Variant::PACKED_FLOAT32_ARRAY: {
			const godot::PackedFloat32Array values = p_value;
			r_values.assign(values.ptr(), values.ptr() + values.size());
			return true;
		}
		case godot::Variant::PACKED_FLOAT64_ARRAY: {
			const godot::PackedFloat64Array values = p_value;
			for (int64_t i = 0; i < values.size(); ++i) {
				if (!push_float(values[i], i, p_dtype, r_values, r_error)) {
					return false;
				}
			}
			return true;
		}
		case godot::Variant::ARRAY: {
			const godot::Array values = p_value;
			for (int64_t i = 0; i < values.size(); ++i) {
				const godot::Variant &value = values[i];
				if (value.get_type() != godot::Variant::INT && value.get_type() != godot::Variant::FLOAT) {
					r_error = "Array element " + std::to_string(i) + " is " + type_name(value) + " but must be a number";
					return false;
				}
				const bool pushed = value.get_type() == godot::Variant::INT ? push_int(value, i, p_dtype, r_values, r_error) : push_float(value, i, p_dtype, r_values, r_error);
				if (!pushed) {
					return false;
				}
			}
			return true;
		}
		default:
			return false;
	}
}

// r_error names a bad Array element
bool read_ints(const godot::Variant &p_value, godot::Variant::Type p_packed_type, int64_t p_min, int64_t p_max, std::vector<int64_t> &r_values, std::string &r_error) {
	r_values.clear();
	if (p_value.get_type() == p_packed_type && p_packed_type == godot::Variant::PACKED_INT32_ARRAY) {
		const godot::PackedInt32Array values = p_value;
		r_values.assign(values.ptr(), values.ptr() + values.size());
		return true;
	}
	if (p_value.get_type() == p_packed_type && p_packed_type == godot::Variant::PACKED_BYTE_ARRAY) {
		const godot::PackedByteArray values = p_value;
		r_values.assign(values.ptr(), values.ptr() + values.size());
		return true;
	}
	if (p_value.get_type() != godot::Variant::ARRAY) {
		return false;
	}
	const godot::Array values = p_value;
	for (int64_t i = 0; i < values.size(); ++i) {
		const godot::Variant &value = values[i];
		if (value.get_type() != godot::Variant::INT) {
			r_error = "Array element " + std::to_string(i) + " is " + type_name(value) + " but must be an int";
			return false;
		}
		const int64_t number = value;
		if (number < p_min || number > p_max) {
			r_error = "Array element " + std::to_string(i) + " is " + std::to_string(number) + ", outside [" + std::to_string(p_min) + ", " + std::to_string(p_max) + "]";
			return false;
		}
		r_values.push_back(number);
	}
	return true;
}

Status convert(const godot::Variant &p_value, const Space &p_space, const std::string &p_path, Point &r_point) {
	std::string error;
	if (const BoxSpace *box = p_space.get_if<BoxSpace>()) {
		const int64_t expected = static_cast<int64_t>(box->low.size());
		BoxPoint point;
		if (!read_floats(p_value, box->dtype, point.values, error)) {
			return error.empty() ? wrong_value(p_path, "PackedFloat32Array", expected, p_space, p_value) : invalid(p_path, error);
		}
		if (static_cast<int64_t>(point.values.size()) != expected) {
			return wrong_value(p_path, "PackedFloat32Array", expected, p_space, p_value);
		}
		r_point = Point(std::move(point));
		return Status::ok();
	}
	if (p_space.get_if<DiscreteSpace>()) {
		if (p_value.get_type() != godot::Variant::INT) {
			return wrong_value(p_path, "int", -1, p_space, p_value);
		}
		const int64_t value = p_value;
		if (value < INT32_LOW || value > INT32_HIGH) {
			return invalid(p_path, "Discrete value " + std::to_string(value) + " is outside the 32-bit integer range");
		}
		r_point = Point(DiscretePoint{ static_cast<int32_t>(value) });
		return Status::ok();
	}
	if (const MultiDiscreteSpace *multi_discrete = p_space.get_if<MultiDiscreteSpace>()) {
		const int64_t expected = static_cast<int64_t>(multi_discrete->nvec.size());
		std::vector<int64_t> values;
		if (!read_ints(p_value, godot::Variant::PACKED_INT32_ARRAY, INT32_LOW, INT32_HIGH, values, error)) {
			return error.empty() ? wrong_value(p_path, "PackedInt32Array", expected, p_space, p_value) : invalid(p_path, error);
		}
		if (static_cast<int64_t>(values.size()) != expected) {
			return wrong_value(p_path, "PackedInt32Array", expected, p_space, p_value);
		}
		r_point = Point(MultiDiscretePoint{ std::vector<int32_t>(values.begin(), values.end()) });
		return Status::ok();
	}
	if (const MultiBinarySpace *multi_binary = p_space.get_if<MultiBinarySpace>()) {
		std::vector<int64_t> values;
		if (!read_ints(p_value, godot::Variant::PACKED_BYTE_ARRAY, 0, 255, values, error)) {
			return error.empty() ? wrong_value(p_path, "PackedByteArray", multi_binary->n, p_space, p_value) : invalid(p_path, error);
		}
		if (static_cast<int64_t>(values.size()) != multi_binary->n) {
			return wrong_value(p_path, "PackedByteArray", multi_binary->n, p_space, p_value);
		}
		r_point = Point(MultiBinaryPoint{ std::vector<uint8_t>(values.begin(), values.end()) });
		return Status::ok();
	}

	const DictSpace *dict = p_space.get_if<DictSpace>();
	if (p_value.get_type() != godot::Variant::DICTIONARY) {
		return wrong_value(p_path, "Dictionary", -1, p_space, p_value);
	}
	const godot::Dictionary values = p_value;
	const godot::Array keys = values.keys();
	std::map<std::string, godot::Variant> by_key;
	for (int64_t i = 0; i < keys.size(); ++i) {
		const godot::Variant &key = keys[i];
		if (!is_string(key)) {
			return invalid(p_path, "Dict key " + to_std_string(key.stringify()) + " is " + type_name(key) + " but must be a String or StringName");
		}
		const std::string name = to_std_string(key);
		if (!by_key.emplace(name, values[key]).second) {
			return invalid(p_path, "Dict value has key '" + name + "' more than once");
		}
		if (dict->find(name) == nullptr) {
			return invalid(p_path, "Dict value has unexpected key '" + name + "'");
		}
	}
	DictPoint point;
	for (const auto &entry : dict->entries) {
		const auto found = by_key.find(entry.first);
		if (found == by_key.end()) {
			return invalid(p_path, "Dict value is missing key '" + entry.first + "'");
		}
		Point entry_point;
		Status status = convert(found->second, entry.second, join_path(p_path, entry.first), entry_point);
		if (!status.is_ok()) {
			return status;
		}
		point.entries.emplace_back(entry.first, std::move(entry_point));
	}
	r_point = Point(std::move(point));
	return Status::ok();
}

godot::PackedFloat32Array to_packed_floats(const std::vector<float> &p_values) {
	godot::PackedFloat32Array result;
	result.resize(static_cast<int64_t>(p_values.size()));
	for (size_t i = 0; i < p_values.size(); ++i) {
		result.set(static_cast<int64_t>(i), p_values[i]);
	}
	return result;
}

godot::PackedInt32Array to_packed_ints(const std::vector<int32_t> &p_values) {
	godot::PackedInt32Array result;
	result.resize(static_cast<int64_t>(p_values.size()));
	for (size_t i = 0; i < p_values.size(); ++i) {
		result.set(static_cast<int64_t>(i), p_values[i]);
	}
	return result;
}

} //namespace

Status variant_to_point(const godot::Variant &p_value, const Space &p_space, Point &r_point) {
	Point point;
	Status status = convert(p_value, p_space, {}, point);
	if (status.is_ok()) {
		status = p_space.validate(point);
	}
	if (status.is_ok()) {
		r_point = std::move(point);
	}
	return status;
}

godot::Variant point_to_variant(const Point &p_point) {
	if (const BoxPoint *box = p_point.get_if<BoxPoint>()) {
		return to_packed_floats(box->values);
	}
	if (const DiscretePoint *discrete = p_point.get_if<DiscretePoint>()) {
		return static_cast<int64_t>(discrete->value);
	}
	if (const MultiDiscretePoint *multi_discrete = p_point.get_if<MultiDiscretePoint>()) {
		return to_packed_ints(multi_discrete->values);
	}
	if (const MultiBinaryPoint *multi_binary = p_point.get_if<MultiBinaryPoint>()) {
		godot::PackedByteArray values;
		values.resize(static_cast<int64_t>(multi_binary->values.size()));
		for (size_t i = 0; i < multi_binary->values.size(); ++i) {
			values.set(static_cast<int64_t>(i), multi_binary->values[i]);
		}
		return values;
	}
	godot::Dictionary values;
	for (const auto &entry : p_point.get_if<DictPoint>()->entries) {
		values[godot::String::utf8(entry.first.c_str())] = point_to_variant(entry.second);
	}
	return values;
}

} //namespace schola
