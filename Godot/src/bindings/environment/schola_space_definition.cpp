// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/schola_space_definition.h"

#include <godot_cpp/core/class_db.hpp>

godot::Ref<ScholaSpaceDefinition> ScholaSpaceDefinition::create(const godot::Ref<ScholaSpace> &p_observation, const godot::Ref<ScholaSpace> &p_action) {
	godot::Ref<ScholaSpaceDefinition> definition;
	definition.instantiate();
	definition->set_observation(p_observation);
	definition->set_action(p_action);
	return definition;
}

void ScholaSpaceDefinition::set_observation(const godot::Ref<ScholaSpace> &p_observation) {
	observation = p_observation;
}

godot::Ref<ScholaSpace> ScholaSpaceDefinition::get_observation() const {
	return observation;
}

void ScholaSpaceDefinition::set_action(const godot::Ref<ScholaSpace> &p_action) {
	action = p_action;
}

godot::Ref<ScholaSpace> ScholaSpaceDefinition::get_action() const {
	return action;
}

void ScholaSpaceDefinition::_bind_methods() {
	godot::ClassDB::bind_static_method("ScholaSpaceDefinition", godot::D_METHOD("create", "observation", "action"), &ScholaSpaceDefinition::create);
	godot::ClassDB::bind_method(godot::D_METHOD("set_observation", "observation"), &ScholaSpaceDefinition::set_observation);
	godot::ClassDB::bind_method(godot::D_METHOD("get_observation"), &ScholaSpaceDefinition::get_observation);
	godot::ClassDB::bind_method(godot::D_METHOD("set_action", "action"), &ScholaSpaceDefinition::set_action);
	godot::ClassDB::bind_method(godot::D_METHOD("get_action"), &ScholaSpaceDefinition::get_action);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::OBJECT, "observation", godot::PROPERTY_HINT_RESOURCE_TYPE, "ScholaSpace"), "set_observation", "get_observation");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::OBJECT, "action", godot::PROPERTY_HINT_RESOURCE_TYPE, "ScholaSpace"), "set_action", "get_action");
}
