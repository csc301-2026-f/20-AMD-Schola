// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/spaces/schola_multi_binary_space.h"

#include "core/spaces/space.h"

#include <godot_cpp/core/class_db.hpp>

void ScholaMultiBinarySpace::set_n(int32_t p_n) {
	n=p_n;
	emit_changed();
}

int32_t ScholaMultiBinarySpace::get_n() const {
	return n;
}

schola::Space ScholaMultiBinarySpace::to_space() const {
	return schola::Space(schola::MultiBinarySpace{ n });
}

void ScholaMultiBinarySpace::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("set_n", "n"), &ScholaMultiBinarySpace::set_n);
	godot::ClassDB::bind_method(godot::D_METHOD("get_n"), &ScholaMultiBinarySpace::get_n);

	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "n"), "set_n", "get_n");
}
