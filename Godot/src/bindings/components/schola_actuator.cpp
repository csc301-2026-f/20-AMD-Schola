// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
#include "bindings/components/schola_actuator.h"
#include "bindings/environment/configuration_diagnostics.h"
#include "bindings/environment/schola_agent.h"
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/core/class_db.hpp>

void ScholaActuator::set_component_id(const godot::String &value) {
	component_id = value;
	refresh_warnings();
}
godot::String ScholaActuator::get_component_id() const {
	return component_id;
}
godot::String ScholaActuator::get_resolved_component_id() const {
	return component_id.is_empty() ? godot::String(get_name()) : component_id;
}
void ScholaActuator::set_space(const godot::Ref<ScholaSpace> &value) {
	const auto callback = callable_mp(this, &ScholaActuator::refresh_warnings);
	if (space.is_valid() && space->is_connected("changed", callback)) {
		space->disconnect("changed", callback);
	}
	space = value;
	if (space.is_valid()) {
		space->connect("changed", callback);
	}
	refresh_warnings();
}
godot::Ref<ScholaSpace> ScholaActuator::get_space() const {
	return space;
}
godot::PackedStringArray ScholaActuator::get_configuration_errors(bool check_duplicates) const {
	godot::PackedStringArray warnings;
	bool found = false;
	for (godot::Node *parent = get_parent(); parent; parent = parent->get_parent()) {
		if (godot::Object::cast_to<ScholaAgent>(parent)) {
			found = true;
			break;
		}
	}
	if (!found) {
		warnings.append("Place this component below a ScholaAgent.");
	}
	if (space.is_null()) {
		warnings.append("space is not set");
	} else if (!space->get_definition_error().is_empty()) {
		warnings.append(space->get_definition_error());
	}
	if (check_duplicates) {
		if (auto *owner = [&]() -> ScholaAgent * {
				for (auto *parent = get_parent(); parent; parent = parent->get_parent()) {
					if (auto *agent = godot::Object::cast_to<ScholaAgent>(parent)) {
						return agent;
					}
				}
				return nullptr;
			}()) {
			for (auto *other : owner->get_actuators()) {
				if (other != this && other->get_resolved_component_id() == get_resolved_component_id()) {
					warnings.append("Duplicate actuator component_id: " + get_resolved_component_id());
					break;
				}
			}
		}
	}
	if (!schola::configuration::has_hook(this, "_act")) {
		warnings.append("Implement _act(action) in this component's script.");
	}
	godot::PackedStringArray extra;
	GDVIRTUAL_CALL(_get_component_errors, extra);
	warnings.append_array(extra);
	return warnings;
}
void ScholaActuator::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_configuration_errors", "check_duplicates"), &ScholaActuator::get_configuration_errors, DEFVAL(true));
	GDVIRTUAL_BIND(_get_component_errors);
	godot::ClassDB::bind_method(godot::D_METHOD("set_component_id", "value"), &ScholaActuator::set_component_id);
	godot::ClassDB::bind_method(godot::D_METHOD("get_component_id"), &ScholaActuator::get_component_id);
	godot::ClassDB::bind_method(godot::D_METHOD("get_resolved_component_id"), &ScholaActuator::get_resolved_component_id);
	godot::ClassDB::bind_method(godot::D_METHOD("set_space", "value"), &ScholaActuator::set_space);
	godot::ClassDB::bind_method(godot::D_METHOD("get_space"), &ScholaActuator::get_space);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::STRING, "component_id"), "set_component_id", "get_component_id");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::OBJECT, "space", godot::PROPERTY_HINT_RESOURCE_TYPE, "ScholaSpace"), "set_space", "get_space");
	GDVIRTUAL_BIND(_act, "action");
}

bool ScholaActuator::apply_value(const godot::Variant &value) {
	return GDVIRTUAL_CALL(_act, value);
}

ScholaActuator::ScholaActuator() {
	connect("script_changed", callable_mp(this, &ScholaActuator::script_updated));
}
ScholaActuator::~ScholaActuator() {
	schola::configuration::disconnect_scripts(watched_scripts, callable_mp(this, &ScholaActuator::script_updated));
	const auto callback = callable_mp(this, &ScholaActuator::refresh_warnings);
	if (space.is_valid() && space->is_connected("changed", callback)) {
		space->disconnect("changed", callback);
	}
}
void ScholaActuator::refresh_warnings() {
	update_configuration_warnings();
	for (auto *parent = get_parent(); parent; parent = parent->get_parent()) {
		if (auto *agent = godot::Object::cast_to<ScholaAgent>(parent)) {
			agent->update_configuration_warnings();
			for (auto *sibling : agent->get_actuators()) {
				if (sibling != this) {
					sibling->update_configuration_warnings();
				}
			}
			break;
		}
	}
}
void ScholaActuator::_notification(int what) {
	const auto callback = callable_mp(this, &ScholaActuator::refresh_warnings);
	if (what == NOTIFICATION_ENTER_TREE) {
		script_updated();
		if (!get_tree()->is_connected("tree_changed", callback)) {
			get_tree()->connect("tree_changed", callback);
		}
		refresh_warnings();
	} else if (what == NOTIFICATION_EXIT_TREE) {
		if (get_tree()->is_connected("tree_changed", callback)) {
			get_tree()->disconnect("tree_changed", callback);
		}
	} else if (what == NOTIFICATION_PATH_RENAMED) {
		refresh_warnings();
	}
}

void ScholaActuator::script_updated() {
	schola::configuration::watch_scripts(this, watched_scripts, callable_mp(this, &ScholaActuator::script_updated));
	refresh_warnings();
}
godot::PackedStringArray ScholaActuator::_get_configuration_warnings() const {
	return get_configuration_errors();
}
