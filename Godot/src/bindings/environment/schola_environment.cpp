// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/schola_environment.h"
#include <godot_cpp/core/class_db.hpp>

void ScholaEnvironment::_bind_methods() {
	godot::ClassDB::bind_method(
		godot::D_METHOD("set_max_episode_steps", "max_episode_steps"),
		&ScholaEnvironment::set_max_episode_steps
	);
	godot::ClassDB::bind_method(
		godot::D_METHOD("get_max_episode_steps"),
		&ScholaEnvironment::get_max_episode_steps
	);
	ADD_PROPERTY(
		godot::PropertyInfo(godot::Variant::INT, "max_episode_steps"),
		"set_max_episode_steps",
		"get_max_episode_steps"
	);
}

godot::PackedStringArray ScholaEnvironment::_get_configuration_warnings() const {
	return {};
}

void ScholaEnvironment::set_max_episode_steps(int32_t p_max_episode_steps) {
	max_episode_steps = p_max_episode_steps;
}

int32_t ScholaEnvironment::get_max_episode_steps() const {
	return max_episode_steps;
}
