// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/adapters/schola_observation_adapter.h"

#include "interop/variant_conversion.h"

#include <utility>

schola::Status ScholaStacker::create(const schola::Space &p_space, std::unique_ptr<schola::ObservationAdapter> &r_adapter) const {
	schola::StackerSettings settings;
	settings.stack_size = stack_size;
	if (default_point.get_type() != godot::Variant::NIL) {
		schola::Point point;
		const schola::Status status = schola::variant_to_point(default_point, p_space, point);
		if (!status.is_ok()) {
			return schola::Status::error(status.get_code(), "default_point: " + status.get_message());
		}
		settings.default_point = std::move(point);
	}

	switch (output_kind) {
		case 0:
			r_adapter = std::make_unique<schola::BoxStacker>(schola::BoxStackerSettings{ std::move(settings), stack_dimension, add_new_dimension });
			break;
		case 1:
			r_adapter = std::make_unique<schola::DictStacker>(std::move(settings));
			break;
		default:
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "output_kind must be Box or Dict");
	}

	return schola::Status::ok();
}

void ScholaStacker::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("set_stack_size", "stack_size"), &ScholaStacker::set_stack_size);
	godot::ClassDB::bind_method(godot::D_METHOD("get_stack_size"), &ScholaStacker::get_stack_size);
	// Same limits the stackers enforce at runtime (and Unreal clamps to), so the
	// Inspector cannot take a value that only fails once training starts.
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "stack_size", godot::PROPERTY_HINT_RANGE, "1,2147483647,1"), "set_stack_size", "get_stack_size");

	godot::ClassDB::bind_method(godot::D_METHOD("set_default_point", "default_point"), &ScholaStacker::set_default_point);
	godot::ClassDB::bind_method(godot::D_METHOD("get_default_point"), &ScholaStacker::get_default_point);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::NIL, "default_point", godot::PROPERTY_HINT_NONE, "", godot::PROPERTY_USAGE_DEFAULT | godot::PROPERTY_USAGE_NIL_IS_VARIANT), "set_default_point", "get_default_point");

	godot::ClassDB::bind_method(godot::D_METHOD("set_stack_dimension", "stack_dimension"), &ScholaStacker::set_stack_dimension);
	godot::ClassDB::bind_method(godot::D_METHOD("get_stack_dimension"), &ScholaStacker::get_stack_dimension);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "stack_dimension", godot::PROPERTY_HINT_RANGE, "0,2147483647,1"), "set_stack_dimension", "get_stack_dimension");

	godot::ClassDB::bind_method(godot::D_METHOD("set_add_new_dimension", "add_new_dimension"), &ScholaStacker::set_add_new_dimension);
	godot::ClassDB::bind_method(godot::D_METHOD("get_add_new_dimension"), &ScholaStacker::get_add_new_dimension);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::BOOL, "add_new_dimension"), "set_add_new_dimension", "get_add_new_dimension");

	godot::ClassDB::bind_method(godot::D_METHOD("set_output_kind", "output_kind"), &ScholaStacker::set_output_kind);
	godot::ClassDB::bind_method(godot::D_METHOD("get_output_kind"), &ScholaStacker::get_output_kind);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "output_kind", godot::PROPERTY_HINT_ENUM, "Box,Dict"), "set_output_kind", "get_output_kind");
}
