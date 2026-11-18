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

// Prefixes every message with the agent's ID so failures say which agent broke.
schola::Status agent_error(const ScholaAgent *p_node, schola::StatusCode p_code, const std::string &p_message) {
	const std::string id = p_node->get_resolved_agent_id().utf8().get_data();
	return schola::Status::error(p_code, "Agent '" + id + "': " + p_message);
}

} // namespace

GodotAgentAdapter::GodotAgentAdapter(ScholaAgent *p_node) :
		node(p_node) {}

schola::Status GodotAgentAdapter::define(schola::InteractionDefinition &r_definition) {
	defined = false;
	// Read the two space resources the developer set in the Inspector.
	// godot::Ref is Godot's smart pointer for resources; it is null when the
	// Inspector field was left empty.
	const godot::Ref<ScholaSpace> observation_resource = node->get_effective_observation_space();
	const godot::Ref<ScholaSpace> action_resource = node->get_effective_action_space();
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
	const auto resources = node->get_observation_adapters();
	for (int64_t i = 0; i < resources.size(); ++i) {
		const godot::Ref<ScholaObservationAdapter> resource = resources[i];
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
	observation_adapters = std::move(adapters);

	// Everything passed. Remember the spaces so observe() and act() can use
	// them, and mark this agent as defined.
	observation_space = new_observation_space;
	action_space = new_action_space;
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
	mutable_dictionary_spaces = node->get_observation_space().is_valid() && godot::Object::cast_to<ScholaDictSpace>(node->get_observation_space().ptr());
	mutable_dictionary_spaces = mutable_dictionary_spaces || (node->get_action_space().is_valid() && godot::Object::cast_to<ScholaDictSpace>(node->get_action_space().ptr()));
	for (auto id : sensors) {
		auto *component = godot::Object::cast_to<ScholaSensor>(godot::ObjectDB::get_instance(id));
		mutable_dictionary_spaces = mutable_dictionary_spaces || godot::Object::cast_to<ScholaDictSpace>(component->get_space().ptr());
	}
	for (auto id : actuators) {
		auto *component = godot::Object::cast_to<ScholaActuator>(godot::ObjectDB::get_instance(id));
		mutable_dictionary_spaces = mutable_dictionary_spaces || godot::Object::cast_to<ScholaDictSpace>(component->get_space().ptr());
	}
	validated_revision = node->get_interaction_revision();
	defined = true;

	// Fill in the caller's definition. agent_type is a godot::String, so it is
	// converted to a std::string the same way as the agent ID.
	r_definition.observation_space = std::move(adapted_space);
	r_definition.action_space = new_action_space;
	r_definition.agent_type = node->get_resolved_agent_type().utf8().get_data();
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
	const auto pre_dispatch_status = check_components();
	if (!pre_dispatch_status.is_ok()) {
		return pre_dispatch_status;
	}
	if (!sensors.empty()) {
		godot::Dictionary values;
		for (size_t i = 0; i < sensors.size(); ++i) {
			auto *component = godot::Object::cast_to<ScholaSensor>(godot::ObjectDB::get_instance(sensors[i]));
			godot::Variant observed;
			if (!component || !component->observe_value(observed)) {
				return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "sensor missing or _observe() not implemented");
			}
			const auto dispatch_status = check_components();
			if (!dispatch_status.is_ok()) {
				return dispatch_status;
			}
			values[godot::String::utf8(observation_space.get_if<schola::DictSpace>()->entries[i].first.c_str())] = observed;
		}
		value = values;
	} else if (!GDVIRTUAL_CALL_PTR(node, _observe, value)) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "_observe() is not overridden");
	}

	const auto final_component_status = check_components();
	if (!final_component_status.is_ok()) {
		return final_component_status;
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
	const auto pre_dispatch_status = check_components();
	if (!pre_dispatch_status.is_ok()) {
		return pre_dispatch_status;
	}
	if (!actuators.empty()) {
		const godot::Dictionary values = schola::point_to_variant(p_action);
		for (size_t i = 0; i < actuators.size(); ++i) {
			auto *component = godot::Object::cast_to<ScholaActuator>(godot::ObjectDB::get_instance(actuators[i]));
			if (!component || !component->apply_value(values[godot::String::utf8(action_space.get_if<schola::DictSpace>()->entries[i].first.c_str())])) {
				return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "actuator missing or _act() not implemented");
			}
			const auto dispatch_status = check_components();
			if (!dispatch_status.is_ok()) {
				return dispatch_status;
			}
		}
	} else if (!GDVIRTUAL_CALL_PTR(node, _act, schola::point_to_variant(p_action))) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "_act() is not overridden");
	}

	return check_components();
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
	auto observation = node->get_effective_observation_space();
	auto action = node->get_effective_action_space();
	changed = changed || observation.is_null() || action.is_null();
	if (!changed) {
		changed = observation->to_space() != observation_space || action->to_space() != action_space;
	}
	if (changed) {
		return agent_error(node, schola::StatusCode::FAILED_PRECONDITION, "component layout or spaces changed; define the agent again");
	}
	const auto runtime_status = check_runtime_components();
	if (!runtime_status.is_ok()) {
		return runtime_status;
	}
	validated_revision = revision;
	return schola::Status::ok();
}
