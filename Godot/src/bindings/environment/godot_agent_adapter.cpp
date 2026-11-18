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

// Starts every message with the agent's ID, so a scene with many agents
// still tells the developer exactly which one is misconfigured.
schola::Status agent_error(const ScholaAgent *p_node, schola::StatusCode p_code, const std::string &p_message) {
	return schola::Status::error(p_code, "Agent '" + to_std_string(p_node->get_resolved_agent_id()) + "': " + p_message);
}

// The only two keys _define_spaces() may return. Each one also names the
// matching Inspector property: "observation" -> observation_space.
constexpr const char *OBSERVATION = "observation";
constexpr const char *ACTION = "action";

// Where an agent's spaces come from. A script with _define_spaces() always
// uses it; every other agent uses its Inspector fields.
enum class SpaceSource {
	INSPECTOR,
	CODE,
};

// Names a space the way the developer wrote it, so an error points at the
// right place: the Inspector property, or the key in the callback's result.
std::string describe_space(SpaceSource p_source, const char *p_key) {
	if (p_source == SpaceSource::CODE) {
		return std::string("_define_spaces()[\"") + p_key + "\"]";
	}
	return std::string(p_key) + "_space";
}

// Names a value's type for error messages: the class for objects
// ("Node"), otherwise the Variant type ("int", "Array").
std::string describe_type(const godot::Variant &p_value) {
	if (p_value.get_type() == godot::Variant::OBJECT) {
		const godot::Object *object = p_value;
		if (object != nullptr) {
			return to_std_string(object->get_class());
		}
	}
	return to_std_string(godot::Variant::get_type_name(p_value.get_type()));
}

// The agent's two space resources, as found and before they are checked.
struct SpaceResources {
	godot::Ref<ScholaSpace> observation;
	godot::Ref<ScholaSpace> action;
};

schola::Status read_inspector_spaces(const ScholaAgent *p_node, SpaceResources &r_resources) {
	r_resources.observation = p_node->get_observation_space();
	r_resources.action = p_node->get_action_space();
	if (r_resources.observation.is_null()) {
		return agent_error(p_node, schola::StatusCode::FAILED_PRECONDITION, "observation_space is not set; assign it in the Inspector or implement _define_spaces()");
	}
	if (r_resources.action.is_null()) {
		return agent_error(p_node, schola::StatusCode::FAILED_PRECONDITION, "action_space is not set; assign it in the Inspector or implement _define_spaces()");
	}
	return schola::Status::ok();
}

// Takes one entry out of the callback's Dictionary and checks that it holds
// a space resource. Whether that space is well formed is checked later, the
// same way for both sources.
schola::Status read_returned_space(const ScholaAgent *p_node, const godot::Dictionary &p_returned, const char *p_key, godot::Ref<ScholaSpace> &r_space) {
	const std::string name = describe_space(SpaceSource::CODE, p_key);
	if (!p_returned.has(p_key)) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, name + " is missing");
	}

	// Three ways an entry can fail to be a space: it's null, it's a plain
	// value (a number, an Array, ...), or it's some other kind of object.
	const godot::Variant value = p_returned[p_key];
	godot::Object *object = value.get_type() == godot::Variant::OBJECT ? static_cast<godot::Object *>(value) : nullptr;
	if (value.get_type() == godot::Variant::NIL || (value.get_type() == godot::Variant::OBJECT && object == nullptr)) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, name + " is null");
	}
	ScholaSpace *space = godot::Object::cast_to<ScholaSpace>(object);
	if (space == nullptr) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, name + " must be a ScholaSpace, not " + describe_type(value));
	}
	r_space = godot::Ref<ScholaSpace>(space);
	return schola::Status::ok();
}

// Runs the developer's _define_spaces() and unpacks its Dictionary.
schola::Status read_code_spaces(ScholaAgent *p_node, SpaceResources &r_resources) {
	godot::Variant returned;
	if (!GDVIRTUAL_CALL_PTR(p_node, _define_spaces, returned)) {
		return agent_error(p_node, schola::StatusCode::FAILED_PRECONDITION, "_define_spaces() could not be called");
	}
	if (returned.get_type() != godot::Variant::DICTIONARY) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, "_define_spaces() must return a Dictionary, not " + describe_type(returned));
	}

	// Reject keys we don't know first. A typo such as "observations" is then
	// reported as itself, instead of as a confusing missing "observation".
	const godot::Dictionary spaces = returned;
	const godot::Array keys = spaces.keys();
	for (int64_t i = 0; i < keys.size(); ++i) {
		const godot::String key = keys[i].stringify();
		if (key != OBSERVATION && key != ACTION) {
			return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, "_define_spaces() returned unknown key \"" + to_std_string(key) + "\"; only \"observation\" and \"action\" are allowed");
		}
	}

	const schola::Status status = read_returned_space(p_node, spaces, OBSERVATION, r_resources.observation);
	if (!status.is_ok()) {
		return status;
	}
	return read_returned_space(p_node, spaces, ACTION, r_resources.action);
}

// Checks that a space resource is well formed (bounds, shapes, Dict
// entries, ...), then copies it into a plain core Space. Nothing links the
// copy back to the resource, so editing the resource later can't change it.
schola::Status to_core_space(const ScholaAgent *p_node, const godot::Ref<ScholaSpace> &p_resource, const std::string &p_name, schola::Space &r_space) {
	const godot::String error = p_resource->get_definition_error();
	if (!error.is_empty()) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, p_name + ": " + to_std_string(error));
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

	// Hand out copies of the saved spaces. agent_type is still read live: it
	// only names the policy this agent shares, and doesn't shape any data.
	r_definition.observation_space = observation_space;
	r_definition.action_space = action_space;
	r_definition.agent_type = to_std_string(node->get_resolved_agent_type());
	return schola::Status::ok();
}

schola::Status GodotAgentAdapter::resolve_spaces() {
	// Python and ONNX models lock in their input and output shapes at
	// startup. So once one caller has seen this agent's spaces, every later
	// caller must see exactly the same ones.
	if (defined) {
		return schola::Status::ok();
	}

	// If _define_spaces() itself leads back to define() (for example by
	// initializing a policy for this agent), we'd recurse forever. Refuse
	// the inner call; the outer one carries on normally.
	if (resolving) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "_define_spaces() must not cause define() to run again");
	}

	// 1. Find the two space resources. The callback wins whenever the
	//    script has one, even if Inspector fields are set too, and a broken
	//    callback result never quietly falls back to those fields.
	const SpaceSource source = node->has_code_defined_spaces() ? SpaceSource::CODE : SpaceSource::INSPECTOR;
	SpaceResources resources;
	resolving = true;
	schola::Status status = source == SpaceSource::CODE ? read_code_spaces(node, resources) : read_inspector_spaces(node, resources);
	resolving = false;
	if (!status.is_ok()) {
		return status;
	}

	// 2. Check and convert both into local variables. If either one fails,
	//    nothing has been saved yet, so the developer can fix the problem
	//    and the next define() simply tries again.
	schola::Space new_observation_space;
	status = to_core_space(node, resources.observation, describe_space(source, OBSERVATION), new_observation_space);
	if (!status.is_ok()) {
		return status;
	}
	schola::Space new_action_space;
	status = to_core_space(node, resources.action, describe_space(source, ACTION), new_action_space);
	if (!status.is_ok()) {
		return status;
	}

	// 3. Both are valid: save them for the rest of this node's life.
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
