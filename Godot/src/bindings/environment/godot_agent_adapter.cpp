// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/godot_agent_adapter.h"

#include "bindings/components/schola_actuator.h"
#include "bindings/components/schola_sensor.h"
#include "bindings/environment/configuration_diagnostics.h"
#include "bindings/environment/schola_agent.h"
#include "bindings/spaces/schola_dict_space.h"
#include "bindings/spaces/schola_space.h"
#include "interop/variant_conversion.h"
#include <godot_cpp/variant/dictionary.hpp>

#include <godot_cpp/classes/ref.hpp>
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

// Each side independently chooses its callback or authored resource.
constexpr const char *OBSERVATION = "observation";
constexpr const char *ACTION = "action";

std::string describe_space(bool p_code, const char *p_key) {
	return p_code ? std::string("_define_") + p_key + "_space()" : std::string(p_key) + "_space";
}

struct SpaceResources {
	godot::Ref<ScholaSpace> observation;
	godot::Ref<ScholaSpace> action;
};

schola::Status read_spaces(ScholaAgent *p_node, SpaceResources &r_resources) {
	for (bool observation : { true, false }) {
		const bool code = observation ? p_node->has_code_defined_observation_space() : p_node->has_code_defined_action_space();
		auto &resource = observation ? r_resources.observation : r_resources.action;
		const std::string name = describe_space(code, observation ? OBSERVATION : ACTION);
		if (code) {
			const bool called = observation ? GDVIRTUAL_CALL_PTR(p_node, _define_observation_space, resource) : GDVIRTUAL_CALL_PTR(p_node, _define_action_space, resource);
			if (!called) {
				return agent_error(p_node, schola::StatusCode::FAILED_PRECONDITION, name + " could not be called");
			}
			if (resource.is_null()) {
				return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, name + " returned null; return a ScholaSpace");
			}
		} else {
			resource = observation ? p_node->get_effective_observation_space() : p_node->get_effective_action_space();
			if (resource.is_null()) {
				return agent_error(p_node, schola::StatusCode::FAILED_PRECONDITION, name + " is not set; assign it in the Inspector or implement _define_" + (observation ? OBSERVATION : ACTION) + "_space()");
			}
		}
	}
	return schola::Status::ok();
}

// Checks that a space resource is well formed (bounds, shapes, Dict
// entries, ...), then copies it into a plain core Space. Nothing links the
// copy back to the resource, so editing the resource later can't change it.
schola::Status to_core_space(const ScholaAgent *p_node, const godot::Ref<ScholaSpace> &p_resource, const std::string &p_name, schola::Space &r_space) {
	if (p_resource.is_null()) {
		return agent_error(p_node, schola::StatusCode::INVALID_ARGUMENT, p_name + " is null");
	}
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
	r_definition.observation_space = adapted_observation_space;
	r_definition.action_space = action_space;
	r_definition.agent_type = to_std_string(node->get_resolved_agent_type());
	return schola::Status::ok();
}

schola::Status GodotAgentAdapter::resolve_spaces() {
	// Python and ONNX models lock in their input and output shapes at
	// startup. So once one caller has seen this agent's spaces, every later
	// caller must see exactly the same ones.
	// Component-authored sides retain US8's explicit redefinition boundary when
	// a new environment initializes the same agent. Authored Inspector sides and
	// callback results remain snapshots; only component composition is rebuilt.
	const bool code_observation = node->has_code_defined_observation_space();
	const bool code_action = node->has_code_defined_action_space();
	const bool refresh_observation = !code_observation && !sensors.empty();
	const bool refresh_action = !code_action && !actuators.empty();
	const bool refresh_components = defined && (refresh_observation || refresh_action);
	if (defined && !refresh_components) {
		return schola::Status::ok();
	}

	// If a space hook itself leads back to define() (for example by
	// initializing a policy for this agent), we'd recurse forever. Refuse
	// the inner call; the outer one carries on normally.
	if (resolving) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "Space-definition hooks must not cause define() to run again");
	}

	// 1. Find the two space resources. The callback wins whenever the
	//    script has one, even if Inspector fields are set too, and a broken
	//    callback result never quietly falls back to those fields.
	SpaceResources resources;
	resolving = true;
	schola::Status status = schola::Status::ok();
	if (refresh_components) {
		resources.observation = node->get_effective_observation_space();
		resources.action = node->get_effective_action_space();
	} else {
		status = read_spaces(node, resources);
	}
	resolving = false;
	if (!status.is_ok()) {
		return status;
	}

	// 2. Check and convert both into local variables. If either one fails,
	//    nothing has been saved yet, so the developer can fix the problem
	//    and the next define() simply tries again.
	schola::Space new_observation_space;
	if (refresh_components && !refresh_observation) {
		new_observation_space = observation_space;
	} else {
		status = to_core_space(node, resources.observation, describe_space(code_observation, OBSERVATION), new_observation_space);
	}
	if (!status.is_ok()) {
		return status;
	}
	schola::Space new_action_space;
	if (refresh_components && !refresh_action) {
		new_action_space = action_space;
	} else {
		status = to_core_space(node, resources.action, describe_space(code_action, ACTION), new_action_space);
	}
	if (!status.is_ok()) {
		return status;
	}

	// 3. Configure observation adapters and component dispatch before publishing.
	// Reject component errors before publishing an interaction definition.
	if (!schola::configuration::has_hook(node, "_observe")) {
		for (auto *component : node->get_sensors()) {
			const auto errors = component->get_configuration_errors();
			if (!errors.is_empty()) {
				return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, errors[0].utf8().get_data());
			}
		}
	}
	if (!schola::configuration::has_hook(node, "_act")) {
		for (auto *component : node->get_actuators()) {
			const auto errors = component->get_configuration_errors();
			if (!errors.is_empty()) {
				return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, errors[0].utf8().get_data());
			}
		}
	}
	schola::Space adapted_space = new_observation_space;
	decltype(observation_adapters) adapters;
	const auto adapter_resources = node->get_observation_adapters();
	for (int64_t i = 0; i < adapter_resources.size(); ++i) {
		const godot::Ref<ScholaObservationAdapter> resource = adapter_resources[i];
		const std::string property = "observation_adapters[" + std::to_string(i) + "]: ";
		if (resource.is_null()) {
			return agent_error(node, schola::StatusCode::INVALID_ARGUMENT, property + "resource is unset");
		}

		std::unique_ptr<schola::ObservationAdapter> adapter;
		status = resource->create(adapted_space, adapter);
		schola::Space output_space;
		if (status.is_ok()) {
			status = adapter->configure(adapted_space, output_space);
		}
		if (!status.is_ok()) {
			return agent_error(node, status.get_code(), property + status.get_message());
		}

		adapter->reset();
		adapted_space = std::move(output_space);
		adapters.push_back(std::move(adapter));
	}
	// Component dispatch indexes the declared Dict entries; refuse incompatible
	// callback declarations before any sensor or actuator can consume them.
	if (code_observation || code_action) {
		if (code_observation && !schola::configuration::has_hook(node, "_observe") && !node->get_sensors().empty() &&
				node->get_effective_observation_space()->to_space() != new_observation_space) {
			return agent_error(node, schola::StatusCode::INVALID_ARGUMENT, "_define_observation_space() must match the sensor composition when _observe() is absent");
		}
		if (code_action && !schola::configuration::has_hook(node, "_act") && !node->get_actuators().empty() &&
				node->get_effective_action_space()->to_space() != new_action_space) {
			return agent_error(node, schola::StatusCode::INVALID_ARGUMENT, "_define_action_space() must match the actuator composition when _act() is absent");
		}
	}

	observation_adapters = std::move(adapters);
	adapted_observation_space = std::move(adapted_space);
	sensors.clear();
	actuators.clear();
	if (!schola::configuration::has_hook(node, "_observe")) {
		for (auto *component : node->get_sensors()) {
			sensors.emplace_back(component->get_instance_id());
		}
	}
	if (!schola::configuration::has_hook(node, "_act")) {
		for (auto *component : node->get_actuators()) {
			actuators.emplace_back(component->get_instance_id());
		}
	}
	// Only user-owned Dict resources need polling: their exposed Dictionaries can
	// change without a Resource.changed signal. Generated composition is private.
	mutable_dictionary_spaces = false;
	for (auto id : sensors) {
		auto *component = godot::Object::cast_to<ScholaSensor>(godot::ObjectDB::get_instance(id));
		mutable_dictionary_spaces = mutable_dictionary_spaces || godot::Object::cast_to<ScholaDictSpace>(component->get_space().ptr());
	}
	for (auto id : actuators) {
		auto *component = godot::Object::cast_to<ScholaActuator>(godot::ObjectDB::get_instance(id));
		mutable_dictionary_spaces = mutable_dictionary_spaces || godot::Object::cast_to<ScholaDictSpace>(component->get_space().ptr());
	}
	validated_revision = node->get_interaction_revision();

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

	const auto component_status = check_components();
	if (!component_status.is_ok()) {
		return component_status;
	}
	const auto runtime_status = check_runtime_components();
	if (!runtime_status.is_ok()) {
		return runtime_status;
	}
	if (!sensors.empty()) {
		godot::Dictionary values;
		for (size_t i = 0; i < sensors.size(); ++i) {
			auto *component = godot::Object::cast_to<ScholaSensor>(godot::ObjectDB::get_instance(sensors[i]));
			godot::Variant observed;
			if (!component || !component->observe_value(observed)) {
				return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "sensor missing or _observe() not implemented");
			}
			values[godot::String::utf8(observation_space.get_if<schola::DictSpace>()->entries[i].first.c_str())] = observed;
		}
		value = values;
	} else if (!GDVIRTUAL_CALL_PTR(node, _observe, value)) {
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

	for (std::size_t i = 0; i < observation_adapters.size(); ++i) {
		schola::Point output;
		const auto adapted = observation_adapters[i]->adapt(observation, output);
		if (!adapted.is_ok()) {
			return agent_error(node, adapted.get_code(), "observation_adapters[" + std::to_string(i) + "]: " + adapted.get_message());
		}
		observation = std::move(output);
	}

	// Success: hand the Point to the caller without copying it again.
	r_observation = std::move(observation);
	return schola::Status::ok();
}

void GodotAgentAdapter::reset_observation_history() {
	for (const auto &adapter : observation_adapters) {
		adapter->reset();
	}
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
	const auto component_status = check_components();
	if (!component_status.is_ok()) {
		return component_status;
	}
	const auto runtime_status = check_runtime_components();
	if (!runtime_status.is_ok()) {
		return runtime_status;
	}
	if (!actuators.empty()) {
		const godot::Dictionary values = schola::point_to_variant(p_action);
		for (size_t i = 0; i < actuators.size(); ++i) {
			auto *component = godot::Object::cast_to<ScholaActuator>(godot::ObjectDB::get_instance(actuators[i]));
			if (!component || !component->apply_value(values[godot::String::utf8(action_space.get_if<schola::DictSpace>()->entries[i].first.c_str())])) {
				return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "actuator missing or _act() not implemented");
			}
		}
	} else if (!GDVIRTUAL_CALL_PTR(node, _act, schola::point_to_variant(p_action))) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "_act() is not overridden");
	}

	return schola::Status::ok();
}

schola::Status GodotAgentAdapter::check_runtime_components() const {
	for (auto id : sensors) {
		auto *component = godot::Object::cast_to<ScholaSensor>(godot::ObjectDB::get_instance(id));
		if (!component) {
			return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "component removed; define the agent again");
		}
		const auto errors = component->get_runtime_errors();
		if (!errors.is_empty()) {
			return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, errors[0].utf8().get_data());
		}
	}
	for (auto id : actuators) {
		auto *component = godot::Object::cast_to<ScholaActuator>(godot::ObjectDB::get_instance(id));
		if (!component) {
			return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "component removed; define the agent again");
		}
		const auto errors = component->get_runtime_errors();
		if (!errors.is_empty()) {
			return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, errors[0].utf8().get_data());
		}
	}
	return schola::Status::ok();
}

schola::Status GodotAgentAdapter::check_components() {
	if (sensors.empty() && actuators.empty()) {
		return schola::Status::ok();
	}
	const uint64_t revision = node->get_interaction_revision();
	if (!mutable_dictionary_spaces && revision == validated_revision) {
		return schola::Status::ok();
	}
	auto current_sensors = node->get_sensors();
	auto current_actuators = node->get_actuators();
	bool changed = (!sensors.empty() && schola::configuration::has_hook(node, "_observe")) || (!actuators.empty() && schola::configuration::has_hook(node, "_act"));
	if (!sensors.empty()) {
		changed = changed || current_sensors.size() != sensors.size();
		for (size_t i = 0; !changed && i < sensors.size(); ++i) {
			changed = godot::ObjectID(current_sensors[i]->get_instance_id()) != sensors[i];
		}
	}
	if (!actuators.empty()) {
		changed = changed || current_actuators.size() != actuators.size();
		for (size_t i = 0; !changed && i < actuators.size(); ++i) {
			changed = godot::ObjectID(current_actuators[i]->get_instance_id()) != actuators[i];
		}
	}
	if (!changed) {
		if (!sensors.empty()) {
			for (auto *component : current_sensors) {
				if (!schola::configuration::has_hook(component, "_observe")) {
					return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "sensor _observe() is not implemented");
				}
			}
		}
		if (!actuators.empty()) {
			for (auto *component : current_actuators) {
				if (!schola::configuration::has_hook(component, "_act")) {
					return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "actuator _act() is not implemented");
				}
			}
		}
	}
	// Only composed sides follow live component layouts. Explicit Inspector and
	// callback resources are snapshots and may be edited without invalidating them.
	if (!sensors.empty()) {
		auto observation = node->get_effective_observation_space();
		changed = changed || observation.is_null() || observation->to_space() != observation_space;
	}
	if (!actuators.empty()) {
		auto action = node->get_effective_action_space();
		changed = changed || action.is_null() || action->to_space() != action_space;
	}
	if (changed) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "component layout or spaces changed; define the agent again");
	}
	validated_revision = revision;
	return schola::Status::ok();
}
