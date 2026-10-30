// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/godot_agent_adapter.h"

#include "bindings/environment/schola_agent.h"
#include "bindings/spaces/schola_space.h"
#include "interop/variant_conversion.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <string>
#include <utility>

namespace {

// Prefixes every message with the agent's ID so failures say which agent broke.
schola::Status agent_error(const ScholaAgent *p_node, schola::StatusCode p_code, const std::string &p_message) {
	const std::string id = p_node->get_agent_id().utf8().get_data();
	return schola::Status::error(p_code, "Agent '" + id + "': " + p_message);
}

} // namespace

GodotAgentAdapter::GodotAgentAdapter(ScholaAgent *p_node) :
		node(p_node) {}

schola::Status GodotAgentAdapter::define(schola::InteractionDefinition &r_definition) {
	// Read the two space resources the developer set in the Inspector.
	// godot::Ref is Godot's smart pointer for resources; it is null when the
	// Inspector field was left empty.
	const godot::Ref<ScholaSpace> observation_resource = node->get_observation_space();
	const godot::Ref<ScholaSpace> action_resource = node->get_action_space();
	if (observation_resource.is_null() || action_resource.is_null()) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "observation_space and action_space must both be set");
	}

	// Turn each Inspector resource into a core Space. Keep them in local
	// variables for now, so nothing changes if a check below fails.
	const schola::Space new_observation_space = observation_resource->to_space();
	const schola::Space new_action_space = action_resource->to_space();

	// Make sure each space is well formed, for example a Box whose low is not
	// above its high. The message says which space was wrong.
	schola::Status status = new_observation_space.check_definition();
	if (!status.is_ok()) {
		return agent_error(node, status.get_code(), "observation_space: " + status.get_message());
	}
	status = new_action_space.check_definition();
	if (!status.is_ok()) {
		return agent_error(node, status.get_code(), "action_space: " + status.get_message());
	}

	// Everything passed. Remember the spaces so observe() and act() can use
	// them, and mark this agent as defined.
	observation_space = new_observation_space;
	action_space = new_action_space;
	defined = true;

	// Fill in the caller's definition. agent_type is a godot::String, so it is
	// converted to a std::string the same way as the agent ID.
	r_definition.observation_space = new_observation_space;
	r_definition.action_space = new_action_space;
	r_definition.agent_type = node->get_agent_type().utf8().get_data();
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
