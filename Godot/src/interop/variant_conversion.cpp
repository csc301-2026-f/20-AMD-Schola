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

#include <cstdint>
#include <limits>
#include <map>
#include <string>
#include <vector>

namespace schola {

namespace {

constexpr int64_t INT32_LOW = std::numeric_limits<int32_t>::min();
constexpr int64_t INT32_HIGH = std::numeric_limits<int32_t>::max();
constexpr int DTYPE_COUNT = static_cast<int>(DType::BOOL) + 1;

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
	return "At '" + p_path + "': " + p_message;
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

// Returns false when p_value is not a list of numbers; r_error names a bad Array element
bool read_floats(const godot::Variant &p_value, std::vector<float> &r_values, std::string &r_error) {
	switch (p_value.get_type()) {
		case godot::Variant::PACKED_FLOAT32_ARRAY: {
			const godot::PackedFloat32Array values = p_value;
			r_values.assign(values.ptr(), values.ptr() + values.size());
			return true;
		}
		case godot::Variant::PACKED_FLOAT64_ARRAY: {
			const godot::PackedFloat64Array values = p_value;
			r_values.assign(values.ptr(), values.ptr() + values.size());
			return true;
		}
		case godot::Variant::ARRAY: {
			const godot::Array values = p_value;
			r_values.clear();
			for (int64_t i = 0; i < values.size(); ++i) {
				const godot::Variant &value = values[i];
				if (value.get_type() != godot::Variant::INT && value.get_type() != godot::Variant::FLOAT) {
					r_error = "Array element " + std::to_string(i) + " is " + type_name(value) + " but must be a number";
					return false;
				}
				r_values.push_back(static_cast<float>(static_cast<double>(value)));
			}
			return true;
		}
		default:
			return false;
	}
}

// Returns false when p_value is neither p_packed_type nor an Array of int; r_error names a bad Array element
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
		if (!read_floats(p_value, point.values, error)) {
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

Status get_field(const godot::Dictionary &p_dictionary, const char *p_name, godot::Variant::Type p_type, const std::string &p_path, godot::Variant &r_value) {
	if (!p_dictionary.has(p_name)) {
		return invalid(p_path, std::string("space Dictionary is missing '") + p_name + "'");
	}
	r_value = p_dictionary[p_name];
	if (r_value.get_type() != p_type) {
		return invalid(p_path, std::string("space Dictionary field '") + p_name + "' must be " + to_std_string(godot::Variant::get_type_name(p_type)) + " but is " + type_name(r_value));
	}
	return Status::ok();
}

Status get_int32(const godot::Dictionary &p_dictionary, const char *p_name, const std::string &p_path, int32_t &r_value) {
	godot::Variant value;
	Status status = get_field(p_dictionary, p_name, godot::Variant::INT, p_path, value);
	if (!status.is_ok()) {
		return status;
	}
	const int64_t number = value;
	if (number < INT32_LOW || number > INT32_HIGH) {
		return invalid(p_path, std::string("space Dictionary field '") + p_name + "' is outside the 32-bit integer range");
	}
	r_value = static_cast<int32_t>(number);
	return Status::ok();
}

Status parse_space(const godot::Variant &p_value, const std::string &p_path, Space &r_space) {
	if (p_value.get_type() != godot::Variant::DICTIONARY) {
		return invalid(p_path, "expected a space Dictionary but got " + type_name(p_value));
	}
	const godot::Dictionary dictionary = p_value;
	const godot::Variant kind_value = dictionary.get("kind", godot::Variant());
	if (!is_string(kind_value)) {
		return invalid(p_path, "space Dictionary needs a String 'kind'");
	}
	const std::string kind = to_std_string(kind_value);
	godot::Variant value;
	Status status = Status::ok();

	if (kind == "box") {
		BoxSpace box;
		const char *bound_names[] = { "low", "high" };
		std::vector<float> *bounds[] = { &box.low, &box.high };
		for (int i = 0; i < 2; ++i) {
			status = get_field(dictionary, bound_names[i], godot::Variant::PACKED_FLOAT32_ARRAY, p_path, value);
			if (!status.is_ok()) {
				return status;
			}
			const godot::PackedFloat32Array bound = value;
			bounds[i]->assign(bound.ptr(), bound.ptr() + bound.size());
		}
		status = get_field(dictionary, "shape", godot::Variant::PACKED_INT32_ARRAY, p_path, value);
		if (!status.is_ok()) {
			return status;
		}
		const godot::PackedInt32Array shape = value;
		box.shape.assign(shape.ptr(), shape.ptr() + shape.size());
		if (dictionary.has("dtype")) {
			int32_t dtype = 0;
			status = get_int32(dictionary, "dtype", p_path, dtype);
			if (!status.is_ok()) {
				return status;
			}
			if (dtype < 0 || dtype >= DTYPE_COUNT) {
				return invalid(p_path, "space Dictionary dtype " + std::to_string(dtype) + " is not a known DType");
			}
			box.dtype = static_cast<DType>(dtype);
		}
		r_space = Space(std::move(box));
	} else if (kind == "discrete") {
		DiscreteSpace discrete;
		status = get_int32(dictionary, "n", p_path, discrete.n);
		r_space = Space(discrete);
	} else if (kind == "multi_discrete") {
		status = get_field(dictionary, "nvec", godot::Variant::PACKED_INT32_ARRAY, p_path, value);
		if (status.is_ok()) {
			const godot::PackedInt32Array nvec = value;
			r_space = Space(MultiDiscreteSpace{ std::vector<int32_t>(nvec.ptr(), nvec.ptr() + nvec.size()) });
		}
	} else if (kind == "multi_binary") {
		MultiBinarySpace multi_binary;
		status = get_int32(dictionary, "n", p_path, multi_binary.n);
		r_space = Space(multi_binary);
	} else if (kind == "dict") {
		status = get_field(dictionary, "spaces", godot::Variant::DICTIONARY, p_path, value);
		if (!status.is_ok()) {
			return status;
		}
		const godot::Dictionary spaces = value;
		const godot::Array keys = spaces.keys();
		DictSpace dict;
		for (int64_t i = 0; i < keys.size(); ++i) {
			const godot::Variant &key = keys[i];
			if (!is_string(key)) {
				return invalid(p_path, "Dict space key " + to_std_string(key.stringify()) + " is " + type_name(key) + " but must be a String");
			}
			const std::string name = to_std_string(key);
			Space entry;
			status = parse_space(spaces[key], join_path(p_path, name), entry);
			if (!status.is_ok()) {
				return status;
			}
			dict.entries.emplace_back(name, std::move(entry));
		}
		r_space = Space(std::move(dict));
	} else {
		return invalid(p_path, "unknown space kind '" + kind + "'");
	}
	return status;
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
	return convert(p_value, p_space, {}, r_point);
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
		for (uint8_t value : multi_binary->values) {
			values.push_back(value);
		}
		return values;
	}
	godot::Dictionary values;
	for (const auto &entry : p_point.get_if<DictPoint>()->entries) {
		values[godot::String::utf8(entry.first.c_str())] = point_to_variant(entry.second);
	}
	return values;
}

Status variant_to_space(const godot::Variant &p_value, Space &r_space) {
	Space space;
	Status status = parse_space(p_value, {}, space);
	if (!status.is_ok()) {
		return status;
	}
	status = space.check_definition();
	if (status.is_ok()) {
		r_space = std::move(space);
	}
	return status;
}

godot::Variant space_to_variant(const Space &p_space) {
	godot::Dictionary result;
	if (const BoxSpace *box = p_space.get_if<BoxSpace>()) {
		result["kind"] = "box";
		result["low"] = to_packed_floats(box->low);
		result["high"] = to_packed_floats(box->high);
		result["shape"] = to_packed_ints(box->shape);
		result["dtype"] = static_cast<int64_t>(box->dtype);
	} else if (const DiscreteSpace *discrete = p_space.get_if<DiscreteSpace>()) {
		result["kind"] = "discrete";
		result["n"] = discrete->n;
	} else if (const MultiDiscreteSpace *multi_discrete = p_space.get_if<MultiDiscreteSpace>()) {
		result["kind"] = "multi_discrete";
		result["nvec"] = to_packed_ints(multi_discrete->nvec);
	} else if (const MultiBinarySpace *multi_binary = p_space.get_if<MultiBinarySpace>()) {
		result["kind"] = "multi_binary";
		result["n"] = multi_binary->n;
	} else {
		godot::Dictionary spaces;
		for (const auto &entry : p_space.get_if<DictSpace>()->entries) {
			spaces[godot::String::utf8(entry.first.c_str())] = space_to_variant(entry.second);
		}
		result["kind"] = "dict";
		result["spaces"] = spaces;
	}
	return result;
}

} //namespace schola
