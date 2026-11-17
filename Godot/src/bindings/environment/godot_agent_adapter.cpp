// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/godot_agent_adapter.h"

#include "bindings/environment/schola_agent.h"
#include "bindings/spaces/schola_space.h"
#include "interop/variant_conversion.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <string>
#include <utility>

namespace {

std::string to_std_string(const godot::String &p_value) {
	return p_value.utf8().get_data();
}

// Prefixes every message with the agent's ID so failures say which agent broke.
schola::Status agent_error(const ScholaAgent *p_node, schola::StatusCode p_code, const std::string &p_message) {
	return schola::Status::error(p_code, "Agent '" + to_std_string(p_node->get_resolved_agent_id()) + "': " + p_message);
}

schola::Status read_inspector_spaces(ScholaAgent *p_node, godot::Ref<ScholaSpace> &r_observation, godot::Ref<ScholaSpace> &r_action) {
	r_observation = p_node->get_observation_space();
	r_action = p_node->get_action_space();
	if (r_observation.is_null() || r_action.is_null()) {
		return agent_error(p_node, schola::StatusCode::FAILED_PRECONDITION, "observation_space and action_space must both be set");
	}
	return schola::Status::ok();
}

// Takes one entry out of the callback's Dictionary and checks it is a space.
schola::Status read_code_space(ScholaAgent *p_node, const godot::Dictionary &p_spaces, const char *p_key, godot::Ref<ScholaSpace> &r_space) {
	const std::string label = std::string("_define_spaces() \"") + p_key + "\"";
	if (!p_spaces.has(p_key)) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, label + " is missing");
	}
	const godot::Variant value = p_spaces[p_key];
	if (value.get_type() != godot::Variant::OBJECT) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, label + " must be a ScholaSpace, not " + to_std_string(godot::Variant::get_type_name(value.get_type())));
	}
	godot::Object *object = value;
	if (object == nullptr) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, label + " is null");
	}
	ScholaSpace *space = godot::Object::cast_to<ScholaSpace>(object);
	if (space == nullptr) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, label + " must be a ScholaSpace, not " + to_std_string(object->get_class()));
	}
	r_space = godot::Ref<ScholaSpace>(space);
	return schola::Status::ok();
}

// Calls _define_spaces() and checks the shape of what it returned.
schola::Status read_code_spaces(ScholaAgent *p_node, godot::Ref<ScholaSpace> &r_observation, godot::Ref<ScholaSpace> &r_action) {
	godot::Variant result;
	if (!GDVIRTUAL_CALL_PTR(p_node, _define_spaces, result)) {
		return agent_error(p_node, schola::StatusCode::FAILED_PRECONDITION, "_define_spaces() could not be called");
	}
	if (result.get_type() != godot::Variant::DICTIONARY) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, "_define_spaces() must return a Dictionary, not " + to_std_string(godot::Variant::get_type_name(result.get_type())));
	}

	// Reject extra keys so a typo like "observations" is reported as itself
	// instead of as a missing "observation".
	const godot::Dictionary spaces = result;
	const godot::Array keys = spaces.keys();
	for (int64_t i = 0; i < keys.size(); ++i) {
		const godot::String key = keys[i].stringify();
		if (key != "observation" && key != "action") {
			return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, "_define_spaces() returned unknown key \"" + to_std_string(key) + "\"; only \"observation\" and \"action\" are allowed");
		}
	}

	const schola::Status status = read_code_space(p_node, spaces, "observation", r_observation);
	if (!status.is_ok()) {
		return status;
	}
	return read_code_space(p_node, spaces, "action", r_action);
}

// Checks one space resource and copies it into a plain core value. The copy
// is what gets saved, so later edits to the resource cannot reach it.
schola::Status build_space(const ScholaAgent *p_node, const godot::Ref<ScholaSpace> &p_resource, const std::string &p_label, schola::Space &r_space) {
	const godot::String error = p_resource->get_definition_error();
	if (!error.is_empty()) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, p_label + ": " + to_std_string(error));
	}
	r_space = p_resource->to_space();
	return schola::Status::ok();
}

} // namespace

GodotAgentAdapter::GodotAgentAdapter(ScholaAgent *p_node) :
		node(p_node) {}

schola::Status GodotAgentAdapter::define(schola::InteractionDefinition &r_definition) {
	const schola::Status status = resolve_spaces();
	if (!status.is_ok()) {
		return status;
	}

	// Fill in the caller's definition from the saved copy. agent_type is a
	// godot::String, so it is converted to a std::string like the agent ID.
	r_definition.observation_space = observation_space;
	r_definition.action_space = action_space;
	r_definition.agent_type = to_std_string(node->get_resolved_agent_type());
	return schola::Status::ok();
}

schola::Status GodotAgentAdapter::resolve_spaces() {
	// Python and ONNX models fix their input shapes at startup, so the first
	// answer is the one every later caller must get.
	if (defined) {
		return schola::Status::ok();
	}
	if (resolving) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "_define_spaces() must not cause define() to run again");
	}

	// The callback wins whenever the script has one, even if the Inspector
	// fields are also set. A bad callback result never falls back to them.
	const bool from_code = node->has_code_defined_spaces();
	godot::Ref<ScholaSpace> observation_resource;
	godot::Ref<ScholaSpace> action_resource;
	resolving = true;
	schola::Status status = from_code ? read_code_spaces(node, observation_resource, action_resource) : read_inspector_spaces(node, observation_resource, action_resource);
	resolving = false;
	if (!status.is_ok()) {
		return status;
	}

	// Build both into local variables first, so a failure saves nothing and
	// the next define() can try again.
	schola::Space new_observation_space;
	schola::Space new_action_space;
	status = build_space(node, observation_resource, from_code ? "_define_spaces() \"observation\"" : "observation_space", new_observation_space);
	if (!status.is_ok()) {
		return status;
	}
	status = build_space(node, action_resource, from_code ? "_define_spaces() \"action\"" : "action_space", new_action_space);
	if (!status.is_ok()) {
		return status;
	}

	observation_space = std::move(new_observation_space);
	action_space = std::move(new_action_space);
	defined = true;
	return schola::Status::ok();
}

schola::Status GodotAgentAdapter::observe(schola::Point &r_observation) {
	// We need the observation space from define() to know what shape to
	// convert into, so refuse to run before it.
	if (!defined) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "observe() called before define()");
	}

	// Ask the developer's GDScript _observe() what the agent sees.
	// The call puts the result in `value`, and returns false if the script
	// never wrote an _observe() at all.
	godot::Variant value;

	if (!GDVIRTUAL_CALL_PTR(node, _observe, value)) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "_observe() is not overridden");
	}

	// Turn the Godot value into a core Point. Build it in a local variable
	// first, so the caller's r_observation stays untouched if the value is
	// the wrong type or shape.
	schola::Point observation;
	const schola::Status status = schola::variant_to_point(value, observation_space, observation);
	if (!status.is_ok()) {
		return agent_error(node, status.get_code(), "_observe() returned a bad value: " + status.get_message());
	}

	// Success: hand the Point to the caller without copying it again.
	r_observation = std::move(observation);
	return schola::Status::ok();
}

schola::Status GodotAgentAdapter::act(const schola::Point &p_action) {
	// We need the action space from define() to check the action against,
	// so refuse to run before it.
	if (!defined) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "act() called before define()");
	}

	// Never trust the action. If it doesn't fit the action space, refuse it
	// here, before _act() runs, so the agent doesn't move at all.
	const schola::Status status = action_space.validate(p_action);
	if (!status.is_ok()) {
		return agent_error(node, status.get_code(), "rejected action: " + status.get_message());
	}

	// Turn the core Point into a Godot value and pass it to the developer's
	// GDScript _act(). The call returns false if the script never wrote an
	// _act() at all.
	if (!GDVIRTUAL_CALL_PTR(node, _act, schola::point_to_variant(p_action))) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "_act() is not overridden");
	}

	return schola::Status::ok();
}
