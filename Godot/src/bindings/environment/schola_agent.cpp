// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/schola_agent.h"

#include "bindings/components/schola_actuator.h"
#include "bindings/components/schola_sensor.h"
#include "bindings/environment/configuration_diagnostics.h"
#include "bindings/environment/godot_agent_adapter.h"
#include "bindings/environment/schola_environment.h"
#include "bindings/spaces/schola_dict_space.h"
#include "bindings/spaces/schola_space.h"

#include <godot_cpp/core/class_db.hpp>

#include <memory>

ScholaAgent::ScholaAgent() {
	connect("script_changed", callable_mp(this, &ScholaAgent::on_script_changed));
}

ScholaAgent::~ScholaAgent() {
	schola::configuration::disconnect_scripts(watched_scripts, callable_mp(this, &ScholaAgent::on_script_changed));
	disconnect_space_signals();
}

void ScholaAgent::on_script_changed() {
	schola::configuration::watch_scripts(this, watched_scripts, callable_mp(this, &ScholaAgent::on_script_changed));
	refresh_configuration_warnings();
}

void ScholaAgent::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE:
			on_script_changed();
			break;
		case NOTIFICATION_PATH_RENAMED:
		case NOTIFICATION_EXIT_TREE:
		case NOTIFICATION_PARENTED:
		case NOTIFICATION_UNPARENTED:
			refresh_configuration_warnings();
			break;
	}
}

void ScholaAgent::disconnect_space_signals() {
	const godot::Callable callback = callable_mp(this, &ScholaAgent::refresh_configuration_warnings);
	for (const godot::Ref<ScholaSpace> &space : { observation_space, action_space }) {
		if (space.is_valid() && space->is_connected("changed", callback)) {
			space->disconnect("changed", callback);
		}
	}
}

void ScholaAgent::connect_space_signals() {
	const godot::Callable callback = callable_mp(this, &ScholaAgent::refresh_configuration_warnings);
	for (const godot::Ref<ScholaSpace> &space : { observation_space, action_space }) {
		if (space.is_valid() && !space->is_connected("changed", callback)) {
			space->connect("changed", callback);
		}
	}
}

void ScholaAgent::refresh_configuration_warnings() {
	update_configuration_warnings();
	for (godot::Node *ancestor = get_parent(); ancestor != nullptr; ancestor = ancestor->get_parent()) {
		if (ScholaEnvironment *environment = godot::Object::cast_to<ScholaEnvironment>(ancestor)) {
			// Defer the scan until removals and reparenting have finished.
			environment->queue_configuration_refresh();
			break;
		}
	}
}

void ScholaAgent::set_agent_id(const godot::String &p_agent_id) {
	agent_id = p_agent_id;
	refresh_configuration_warnings();
}

godot::String ScholaAgent::get_agent_id() const {
	return agent_id;
}

void ScholaAgent::set_agent_type(const godot::String &p_agent_type) {
	agent_type = p_agent_type;
}

godot::String ScholaAgent::get_agent_type() const {
	return agent_type;
}

void ScholaAgent::set_observation_space(const godot::Ref<ScholaSpace> &p_observation_space) {
	disconnect_space_signals();
	observation_space = p_observation_space;
	connect_space_signals();
	refresh_configuration_warnings();
}

godot::Ref<ScholaSpace> ScholaAgent::get_observation_space() const {
	if (schola::configuration::has_hook(this, "_observe")) {
		return observation_space;
	}
	auto components = get_sensors();
	if (components.empty()) {
		return observation_space;
	}
	godot::Ref<ScholaDictSpace> combined;
	combined.instantiate();
	godot::Dictionary entries;
	for (size_t i = 0; i < components.size(); ++i) {
		entries[godot::String::num_int64(i).pad_zeros(8) + ":" + components[i]->get_resolved_component_id()] = components[i]->get_space();
	}
	combined->set_spaces(entries);
	return combined;
}

void ScholaAgent::set_action_space(const godot::Ref<ScholaSpace> &p_action_space) {
	disconnect_space_signals();
	action_space = p_action_space;
	connect_space_signals();
	refresh_configuration_warnings();
}

godot::Ref<ScholaSpace> ScholaAgent::get_action_space() const {
	if (schola::configuration::has_hook(this, "_act")) {
		return action_space;
	}
	auto components = get_actuators();
	if (components.empty()) {
		return action_space;
	}
	godot::Ref<ScholaDictSpace> combined;
	combined.instantiate();
	godot::Dictionary entries;
	for (size_t i = 0; i < components.size(); ++i) {
		entries[godot::String::num_int64(i).pad_zeros(8) + ":" + components[i]->get_resolved_component_id()] = components[i]->get_space();
	}
	combined->set_spaces(entries);
	return combined;
}

schola::Agent *ScholaAgent::get_agent() {
	// Create the adapter the first time someone asks for it. It keeps a
	// pointer back to this node, which is safe because this node owns it
	// and deletes it when the node itself is destroyed.
	if (!agent_adapter) {
		agent_adapter = std::make_unique<GodotAgentAdapter>(this);
	}
	return agent_adapter.get();
}

const schola::Agent *ScholaAgent::get_agent() const {
	// Same adapter as above. const_cast lets this read-only version reuse it
	// instead of duplicating the creation logic.
	return const_cast<ScholaAgent *>(this)->get_agent();
}

godot::PackedStringArray ScholaAgent::get_configuration_errors() const {
	godot::PackedStringArray errors;
	const auto effective_observation = get_observation_space();
	const auto effective_action = get_action_space();
	if (effective_observation.is_null()) {
		errors.append("observation_space is not set");
	} else {
		const godot::String error = effective_observation->get_definition_error();
		if (!error.is_empty()) {
			errors.append("observation_space: " + error);
		}
	}
	if (effective_action.is_null()) {
		errors.append("action_space is not set");
	} else {
		const godot::String error = effective_action->get_definition_error();
		if (!error.is_empty()) {
			errors.append("action_space: " + error);
		}
	}
	return errors;
}

void ScholaAgent::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_resolved_agent_id"), &ScholaAgent::get_resolved_agent_id);
	godot::ClassDB::bind_method(godot::D_METHOD("get_resolved_agent_type"), &ScholaAgent::get_resolved_agent_type);
	godot::ClassDB::bind_method(godot::D_METHOD("set_agent_id", "agent_id"), &ScholaAgent::set_agent_id);
	godot::ClassDB::bind_method(godot::D_METHOD("get_agent_id"), &ScholaAgent::get_agent_id);
	godot::ClassDB::bind_method(godot::D_METHOD("set_agent_type", "agent_type"), &ScholaAgent::set_agent_type);
	godot::ClassDB::bind_method(godot::D_METHOD("get_agent_type"), &ScholaAgent::get_agent_type);
	godot::ClassDB::bind_method(godot::D_METHOD("set_observation_space", "observation_space"), &ScholaAgent::set_observation_space);
	godot::ClassDB::bind_method(godot::D_METHOD("get_observation_space"), &ScholaAgent::get_observation_space);
	godot::ClassDB::bind_method(godot::D_METHOD("set_action_space", "action_space"), &ScholaAgent::set_action_space);
	godot::ClassDB::bind_method(godot::D_METHOD("get_action_space"), &ScholaAgent::get_action_space);
	godot::ClassDB::bind_method(godot::D_METHOD("get_configuration_errors"), &ScholaAgent::get_configuration_errors);
	GDVIRTUAL_BIND(_observe);
	GDVIRTUAL_BIND(_act, "action");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::STRING, "agent_id"), "set_agent_id", "get_agent_id");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::STRING, "agent_type"), "set_agent_type", "get_agent_type");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::OBJECT, "observation_space", godot::PROPERTY_HINT_RESOURCE_TYPE, "ScholaSpace"), "set_observation_space", "get_observation_space");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::OBJECT, "action_space", godot::PROPERTY_HINT_RESOURCE_TYPE, "ScholaSpace"), "set_action_space", "get_action_space");
}

godot::PackedStringArray ScholaAgent::_get_configuration_warnings() const {
	godot::PackedStringArray warnings = get_configuration_errors();
	if (get_sensors().empty() && !schola::configuration::has_hook(this, "_observe")) {
		warnings.append("Implement _observe() in this agent's script to return its observation.");
	}
	if (get_actuators().empty() && !schola::configuration::has_hook(this, "_act")) {
		warnings.append("Implement _act(action) in this agent's script to apply an action.");
	}
	return warnings;
}
godot::String ScholaAgent::get_resolved_agent_id() const {
	return agent_id.is_empty() ? godot::String(get_name()) : agent_id;
}

godot::String ScholaAgent::get_resolved_agent_type() const {
	return agent_type.is_empty() ? get_resolved_agent_id() : agent_type;
}

namespace {
template <class T>
void collect_components(const godot::Node *parent, std::vector<T *> &result) {
	for (int i = 0; i < parent->get_child_count(); ++i) {
		auto *child = parent->get_child(i);
		if (godot::Object::cast_to<ScholaAgent>(child)) {
			continue;
		}
		if (auto *component = godot::Object::cast_to<T>(child)) {
			result.push_back(component);
		}
		collect_components(child, result);
	}
}
} //namespace
std::vector<ScholaSensor *> ScholaAgent::get_sensors() const {
	std::vector<ScholaSensor *> result;
	collect_components(this, result);
	return result;
}
std::vector<ScholaActuator *> ScholaAgent::get_actuators() const {
	std::vector<ScholaActuator *> result;
	collect_components(this, result);
	return result;
}
