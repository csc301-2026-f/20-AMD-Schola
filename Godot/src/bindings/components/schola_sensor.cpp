// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
#include "bindings/components/schola_sensor.h"
#include "bindings/environment/configuration_diagnostics.h"
#include "bindings/environment/schola_agent.h"
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/core/class_db.hpp>

void ScholaSensor::set_component_id(const godot::String &value) {
	component_id = value;
	refresh_warnings();
}
godot::String ScholaSensor::get_component_id() const {
	return component_id;
}
godot::String ScholaSensor::get_resolved_component_id() const {
	return component_id.is_empty() ? godot::String(get_name()) : component_id;
}
void ScholaSensor::set_space(const godot::Ref<ScholaSpace> &value) {
	const auto callback = callable_mp(this, &ScholaSensor::refresh_warnings);
	if (space.is_valid() && space->is_connected("changed", callback)) {
		space->disconnect("changed", callback);
	}
	space = value;
	if (space.is_valid()) {
		space->connect("changed", callback);
	}
	refresh_warnings();
}
godot::Ref<ScholaSpace> ScholaSensor::get_space() const {
	return space;
}
godot::PackedStringArray ScholaSensor::get_configuration_errors(bool check_duplicates) const {
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
			for (auto *other : owner->get_sensors()) {
				if (other != this && other->get_resolved_component_id() == get_resolved_component_id()) {
					warnings.append("Duplicate sensor component_id: " + get_resolved_component_id());
					break;
				}
			}
		}
	}
	if (!schola::configuration::has_hook(this, "_observe")) {
		warnings.append("Implement _observe() in this component's script.");
	}
	godot::PackedStringArray extra;
	GDVIRTUAL_CALL(_get_component_errors, extra);
	warnings.append_array(extra);
	return warnings;
}
void ScholaSensor::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_configuration_errors", "check_duplicates"), &ScholaSensor::get_configuration_errors, DEFVAL(true));
	GDVIRTUAL_BIND(_get_component_errors);
	godot::ClassDB::bind_method(godot::D_METHOD("set_component_id", "value"), &ScholaSensor::set_component_id);
	godot::ClassDB::bind_method(godot::D_METHOD("get_component_id"), &ScholaSensor::get_component_id);
	godot::ClassDB::bind_method(godot::D_METHOD("get_resolved_component_id"), &ScholaSensor::get_resolved_component_id);
	godot::ClassDB::bind_method(godot::D_METHOD("set_space", "value"), &ScholaSensor::set_space);
	godot::ClassDB::bind_method(godot::D_METHOD("get_space"), &ScholaSensor::get_space);
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::STRING, "component_id"), "set_component_id", "get_component_id");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::OBJECT, "space", godot::PROPERTY_HINT_RESOURCE_TYPE, "ScholaSpace"), "set_space", "get_space");
	GDVIRTUAL_BIND(_observe);
}

bool ScholaSensor::observe_value(godot::Variant &value) {
	return GDVIRTUAL_CALL(_observe, value);
}

ScholaSensor::ScholaSensor() {
	connect("script_changed", callable_mp(this, &ScholaSensor::script_updated));
}
ScholaSensor::~ScholaSensor() {
	schola::configuration::disconnect_scripts(watched_scripts, callable_mp(this, &ScholaSensor::script_updated));
	const auto callback = callable_mp(this, &ScholaSensor::refresh_warnings);
	if (space.is_valid() && space->is_connected("changed", callback)) {
		space->disconnect("changed", callback);
	}
}
void ScholaSensor::refresh_warnings() {
	update_configuration_warnings();
	for (auto *parent = get_parent(); parent; parent = parent->get_parent()) {
		if (auto *agent = godot::Object::cast_to<ScholaAgent>(parent)) {
			agent->update_configuration_warnings();
			for (auto *sibling : agent->get_sensors()) {
				if (sibling != this) {
					sibling->update_configuration_warnings();
				}
			}
			break;
		}
	}
}
void ScholaSensor::_notification(int what) {
	const auto callback = callable_mp(this, &ScholaSensor::refresh_warnings);
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

void ScholaSensor::script_updated() {
	schola::configuration::watch_scripts(this, watched_scripts, callable_mp(this, &ScholaSensor::script_updated));
	refresh_warnings();
}
godot::PackedStringArray ScholaSensor::_get_configuration_warnings() const {
	return get_configuration_errors();
}
