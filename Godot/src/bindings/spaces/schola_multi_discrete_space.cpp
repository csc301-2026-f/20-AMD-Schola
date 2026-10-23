// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/spaces/schola_multi_discrete_space.h"

#include "core/spaces/space.h"

#include <godot_cpp/core/class_db.hpp>

void ScholaMultiDiscreteSpace::set_nvec(const godot::PackedInt32Array &p_nvec) {
	nvec = p_nvec;
	emit_changed();
}

godot::PackedInt32Array ScholaMultiDiscreteSpace::get_nvec() const {
	return nvec;
}

schola::Space ScholaMultiDiscreteSpace::to_space() const {
	return schola::Space(schola::MultiDiscreteSpace{ std::vector<int32_t>(nvec.ptr(), nvec.ptr() + nvec.size()) });
}

void ScholaMultiDiscreteSpace::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("set_nvec", "nvec"), &ScholaMultiDiscreteSpace::set_nvec);
	godot::ClassDB::bind_method(godot::D_METHOD("get_nvec"), &ScholaMultiDiscreteSpace::get_nvec);

	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::PACKED_INT32_ARRAY, "nvec"), "set_nvec", "get_nvec");
}
