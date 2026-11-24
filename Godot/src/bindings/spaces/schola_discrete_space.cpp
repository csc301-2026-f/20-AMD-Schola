// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/spaces/schola_discrete_space.h"

#include "core/spaces/space.h"

#include <godot_cpp/core/class_db.hpp>

void ScholaDiscreteSpace::set_n(int32_t p_n) {
	n = p_n;
	emit_changed();
}

int32_t ScholaDiscreteSpace::get_n() const {
	return n;
}

schola::Space ScholaDiscreteSpace::to_space() const {
	return schola::Space(schola::DiscreteSpace{ n });
}

void ScholaDiscreteSpace::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("set_n", "n"), &ScholaDiscreteSpace::set_n);
	godot::ClassDB::bind_method(godot::D_METHOD("get_n"), &ScholaDiscreteSpace::get_n);

	// The range starts at the unset 0. Starting at 1 makes the Inspector show 1
	// while n is still 0, and typing 1 then changes nothing.
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "n", godot::PROPERTY_HINT_RANGE, "0,2147483647,1"), "set_n", "get_n");
}
