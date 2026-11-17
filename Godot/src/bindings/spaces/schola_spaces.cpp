// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/spaces/schola_spaces.h"

#include <godot_cpp/core/class_db.hpp>

godot::Ref<ScholaBoxSpace> ScholaSpaces::box(const godot::PackedInt32Array &p_shape, double p_low, double p_high, int32_t p_dtype) {
	godot::PackedFloat32Array low;
	low.push_back(static_cast<float>(p_low));
	godot::PackedFloat32Array high;
	high.push_back(static_cast<float>(p_high));
	return box_bounds(p_shape, low, high, p_dtype);
}

godot::Ref<ScholaBoxSpace> ScholaSpaces::box_bounds(const godot::PackedInt32Array &p_shape, const godot::PackedFloat32Array &p_low, const godot::PackedFloat32Array &p_high, int32_t p_dtype) {
	godot::Ref<ScholaBoxSpace> space;
	space.instantiate();
	space->set_shape(p_shape);
	space->set_low(p_low);
	space->set_high(p_high);
	space->set_dtype(p_dtype);
	return space;
}

godot::Ref<ScholaDiscreteSpace> ScholaSpaces::discrete(int32_t p_n) {
	godot::Ref<ScholaDiscreteSpace> space;
	space.instantiate();
	space->set_n(p_n);
	return space;
}

godot::Ref<ScholaMultiDiscreteSpace> ScholaSpaces::multi_discrete(const godot::PackedInt32Array &p_nvec) {
	godot::Ref<ScholaMultiDiscreteSpace> space;
	space.instantiate();
	space->set_nvec(p_nvec);
	return space;
}

godot::Ref<ScholaMultiBinarySpace> ScholaSpaces::multi_binary(int32_t p_n) {
	godot::Ref<ScholaMultiBinarySpace> space;
	space.instantiate();
	space->set_n(p_n);
	return space;
}

godot::Ref<ScholaDictSpace> ScholaSpaces::dict(const godot::Dictionary &p_spaces) {
	godot::Ref<ScholaDictSpace> space;
	space.instantiate();
	space->set_spaces(p_spaces);
	return space;
}

void ScholaSpaces::_bind_methods() {
	godot::ClassDB::bind_static_method("ScholaSpaces", godot::D_METHOD("box", "shape", "low", "high", "dtype"), &ScholaSpaces::box, DEFVAL(FLOAT32));
	godot::ClassDB::bind_static_method("ScholaSpaces", godot::D_METHOD("box_bounds", "shape", "low", "high", "dtype"), &ScholaSpaces::box_bounds, DEFVAL(godot::PackedFloat32Array()), DEFVAL(godot::PackedFloat32Array()), DEFVAL(FLOAT32));
	godot::ClassDB::bind_static_method("ScholaSpaces", godot::D_METHOD("discrete", "n"), &ScholaSpaces::discrete);
	godot::ClassDB::bind_static_method("ScholaSpaces", godot::D_METHOD("multi_discrete", "nvec"), &ScholaSpaces::multi_discrete);
	godot::ClassDB::bind_static_method("ScholaSpaces", godot::D_METHOD("multi_binary", "n"), &ScholaSpaces::multi_binary);
	godot::ClassDB::bind_static_method("ScholaSpaces", godot::D_METHOD("dict", "spaces"), &ScholaSpaces::dict);
	BIND_ENUM_CONSTANT(FLOAT32);
	BIND_ENUM_CONSTANT(UINT8);
	BIND_ENUM_CONSTANT(UINT16);
	BIND_ENUM_CONSTANT(UINT32);
	BIND_ENUM_CONSTANT(UINT64);
	BIND_ENUM_CONSTANT(INT8);
	BIND_ENUM_CONSTANT(INT16);
	BIND_ENUM_CONSTANT(INT32);
	BIND_ENUM_CONSTANT(INT64);
	BIND_ENUM_CONSTANT(FLOAT16);
	BIND_ENUM_CONSTANT(FLOAT64);
	BIND_ENUM_CONSTANT(BOOL);
}
