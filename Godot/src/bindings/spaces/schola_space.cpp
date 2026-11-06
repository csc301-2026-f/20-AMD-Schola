// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/spaces/schola_space.h"

#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"
#include "interop/space_dictionary.h"
#include "interop/variant_conversion.h"

#include <godot_cpp/core/class_db.hpp>

namespace {

godot::String to_godot_string(const std::string &p_value) {
	return godot::String::utf8(p_value.c_str());
}

} // namespace

godot::String ScholaSpace::get_resource_error(const godot::String &) const {
	return godot::String();
}

godot::String ScholaSpace::build_space(schola::Space &r_space) const {
	const godot::String resource_error = get_resource_error(godot::String());
	if (!resource_error.is_empty()) {
		return resource_error;
	}
	r_space = to_space();
	const schola::Status status = r_space.check_definition();
	return status.is_ok() ? godot::String() : to_godot_string(status.get_message());
}

godot::String ScholaSpace::get_validation_error(const godot::Variant &p_value) const {
	schola::Space space;
	const godot::String definition_error = build_space(space);
	if (!definition_error.is_empty()) {
		return "invalid space definition: " + definition_error;
	}
	schola::Point point;
	const schola::Status status = schola::variant_to_point(p_value, space, point);
	return status.is_ok() ? godot::String() : to_godot_string(status.get_message());
}

godot::String ScholaSpace::get_definition_error() const {
	schola::Space space;
	return build_space(space);
}

godot::Dictionary ScholaSpace::to_dictionary() const {
	return schola::space_to_dictionary(to_space());
}

int64_t ScholaSpace::get_flattened_size() const {
	schola::Space space;
	return build_space(space).is_empty() ? space.get_flattened_size() : 0;
}

godot::Variant ScholaSpace::make_default_value() const {
	schola::Space space;
	if (!build_space(space).is_empty()) {
		return godot::Variant();
	}
	return schola::point_to_variant(space.make_point());
}

godot::String ScholaSpace::describe() const {
	return to_godot_string(to_space().to_string());
}

void ScholaSpace::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_validation_error", "value"), &ScholaSpace::get_validation_error);
	godot::ClassDB::bind_method(godot::D_METHOD("get_definition_error"), &ScholaSpace::get_definition_error);
	godot::ClassDB::bind_method(godot::D_METHOD("to_dictionary"), &ScholaSpace::to_dictionary);
	godot::ClassDB::bind_method(godot::D_METHOD("get_flattened_size"), &ScholaSpace::get_flattened_size);
	godot::ClassDB::bind_method(godot::D_METHOD("make_default_value"), &ScholaSpace::make_default_value);
	godot::ClassDB::bind_method(godot::D_METHOD("describe"), &ScholaSpace::describe);
}
