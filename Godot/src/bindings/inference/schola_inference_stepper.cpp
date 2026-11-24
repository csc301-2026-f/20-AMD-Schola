// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/inference/schola_inference_stepper.h"

#include "bindings/environment/schola_agent.h"
#include "core/environment/interaction_definition.h"
#include "core/stepper/simple_stepper.h"
#include "inference/onnx_policy.h"
#include "interop/godot_status.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

namespace {

// The stepper only compares a new agent with the agents it already has. Once
// those are gone, the policy still holds the old agent's spaces (and maybe
// another stepper's), so an agent joining an empty stepper is checked here.
bool fits_policy(ScholaAgent *p_agent, const ScholaOnnxPolicy &p_policy) {
	schola::InteractionDefinition definition;
	if (!p_agent->get_agent()->define(definition).is_ok()) {
		return true; // add_agent() reports the define() failure itself
	}
	const schola::InteractionDefinition *expected = p_policy.get_definition();
	return definition.observation_space == expected->observation_space && definition.action_space == expected->action_space;
}

} // namespace

ScholaInferenceStepper::ScholaInferenceStepper() = default;

ScholaInferenceStepper::~ScholaInferenceStepper() {
	const godot::Callable callback = callable_mp(this, &ScholaInferenceStepper::refresh_warnings);
	if (policy.is_valid() && policy->is_connected("changed", callback)) {
		policy->disconnect("changed", callback);
	}
}

void ScholaInferenceStepper::set_policy(const godot::Ref<ScholaOnnxPolicy> &p_policy) {
	if (p_policy == policy) {
		return;
	}
	if (stepping) {
		(void)report("ScholaInferenceStepper.policy: cannot change the policy during a step; use set_deferred(\"policy\", value)", godot::ERR_BUSY);
		return;
	}
	// Follow the policy's own edits too, so picking a model_path clears the
	// "no model_path" warning without reassigning the policy.
	const godot::Callable callback = callable_mp(this, &ScholaInferenceStepper::refresh_warnings);
	if (policy.is_valid() && policy->is_connected("changed", callback)) {
		policy->disconnect("changed", callback);
	}
	policy = p_policy;
	if (policy.is_valid()) {
		policy->connect("changed", callback);
	}
	if (stepper != nullptr) {
		stepper.reset();
		// The old agents are gone, so forget their last failure. Otherwise the
		// same failure from the re-added agents looks like a repeat and stays quiet.
		last_step_error = godot::String();
		(void)report("ScholaInferenceStepper.policy: the policy was changed, so its agents were removed; add them again", godot::ERR_UNCONFIGURED);
	}
	update_configuration_warnings();
}

godot::Ref<ScholaOnnxPolicy> ScholaInferenceStepper::get_policy() const {
	return policy;
}

void ScholaInferenceStepper::set_agents(const godot::TypedArray<godot::NodePath> &p_agents) {
	agents = p_agents;
	update_configuration_warnings();
}

godot::TypedArray<godot::NodePath> ScholaInferenceStepper::get_agents() const {
	return agents;
}

void ScholaInferenceStepper::set_enabled(bool p_enabled) {
	enabled = p_enabled;
}

bool ScholaInferenceStepper::is_enabled() const {
	return enabled;
}

godot::Error ScholaInferenceStepper::add_agent(ScholaAgent *p_agent) {
	if (stepping) {
		return report("ScholaInferenceStepper.add_agent: cannot add agents during a step; use call_deferred(\"add_agent\", agent)", godot::ERR_BUSY);
	}
	godot::Error error = prepare(p_agent);
	if (error != godot::OK) {
		return error;
	}
	int32_t index = -1;
	schola::Status status = stepper->add_agent(p_agent->get_agent(), index);
	if (!status.is_ok()) {
		return report("ScholaInferenceStepper.add_agent", status);
	}
	const godot::Callable on_exiting = callable_mp(this, &ScholaInferenceStepper::on_agent_exiting).bind(p_agent);
	if (!p_agent->is_connected("tree_exiting", on_exiting)) {
		p_agent->connect("tree_exiting", on_exiting);
	}
	return godot::OK;
}

int32_t ScholaInferenceStepper::remove_agent(ScholaAgent *p_agent) {
	if (p_agent == nullptr) {
		return 0;
	}
	const godot::Callable on_exiting = callable_mp(this, &ScholaInferenceStepper::on_agent_exiting).bind(p_agent);
	if (p_agent->is_connected("tree_exiting", on_exiting)) {
		p_agent->disconnect("tree_exiting", on_exiting);
	}
	if (stepper == nullptr) {
		return 0;
	}
	return stepper->remove_agent(p_agent->get_agent());
}

void ScholaInferenceStepper::reset_state(ScholaAgent *p_agent) {
	if (stepper == nullptr || p_agent == nullptr) {
		return;
	}
	for (int32_t i = 0; i < stepper->get_agent_count(); ++i) {
		if (stepper->get_agent(i) == p_agent->get_agent()) {
			(void)stepper->reset_state(i);
		}
	}
}

void ScholaInferenceStepper::reset_states() {
	if (stepper != nullptr) {
		stepper->reset_states();
	}
}

godot::Error ScholaInferenceStepper::step() {
	if (stepper == nullptr) {
		return godot::OK;
	}
	const bool was_stepping = stepping;
	stepping = true;
	schola::Status status = stepper->step();
	stepping = was_stepping;
	if (status.is_ok()) {
		last_step_error = godot::String();
		return godot::OK;
	}
	const godot::String message = godot::String("ScholaInferenceStepper.step: ") + to_godot_string(status.get_message());
	if (message == last_step_error) {
		return to_godot_error(status);
	}
	last_step_error = message;
	return report(message, to_godot_error(status));
}

godot::PackedStringArray ScholaInferenceStepper::get_configuration_errors() const {
	godot::PackedStringArray errors;
	if (policy.is_null()) {
		errors.push_back("Set a ScholaOnnxPolicy in the policy property.");
	} else if (policy->get_model_path().is_empty()) {
		errors.push_back("The policy has no model_path.");
	}
	if (is_inside_tree()) {
		for (int64_t i = 0; i < agents.size(); ++i) {
			const godot::NodePath path = agents[i];
			if (godot::Object::cast_to<ScholaAgent>(get_node_or_null(path)) == nullptr) {
				errors.push_back("Agent '" + godot::String(path) + "' is not a ScholaAgent.");
			}
		}
	}
	return errors;
}

godot::PackedStringArray ScholaInferenceStepper::_get_configuration_warnings() const {
	return get_configuration_errors();
}

void ScholaInferenceStepper::_ready() {
	if (godot::Engine::get_singleton()->is_editor_hint()) {
		set_physics_process(false);
		return;
	}
	for (int64_t i = 0; i < agents.size(); ++i) {
		const godot::NodePath path = agents[i];
		ScholaAgent *agent = godot::Object::cast_to<ScholaAgent>(get_node_or_null(path));
		if (agent == nullptr) {
			(void)report("ScholaInferenceStepper.agents: '" + godot::String(path) + "' is not a ScholaAgent", godot::ERR_INVALID_PARAMETER);
			continue;
		}
		(void)add_agent(agent);
	}
}

void ScholaInferenceStepper::_physics_process([[maybe_unused]] double p_delta) {
	if (enabled) {
		(void)step();
	}
}

godot::Error ScholaInferenceStepper::prepare(ScholaAgent *p_agent) {
	if (p_agent == nullptr || !p_agent->is_inside_tree()) {
		return report("ScholaInferenceStepper.add_agent: the agent must be a ScholaAgent inside the scene tree", godot::ERR_INVALID_PARAMETER);
	}
	if (policy.is_null()) {
		return report("ScholaInferenceStepper.add_agent: set a ScholaOnnxPolicy in the policy property", godot::ERR_UNCONFIGURED);
	}
	if (!policy->is_initialized()) {
		const godot::Error error = policy->initialize(p_agent);
		if (error != godot::OK) {
			emit_signal("inference_failed", policy->get_last_error());
			return error;
		}
	} else if ((stepper == nullptr || stepper->get_agent_count() == 0) && !fits_policy(p_agent, *policy.ptr())) {
		return report("ScholaInferenceStepper.add_agent: the agent's spaces differ from the ones the policy was initialized with; call policy.initialize(agent) to switch it", godot::ERR_INVALID_DATA);
	}
	if (stepper == nullptr) {
		stepper = std::make_unique<schola::SimpleStepper>();
		schola::Status status = stepper->init({}, policy->get_policy());
		if (!status.is_ok()) {
			stepper.reset();
			return report("ScholaInferenceStepper.add_agent", status);
		}
	}
	return godot::OK;
}

void ScholaInferenceStepper::refresh_warnings() {
	update_configuration_warnings();
}

void ScholaInferenceStepper::on_agent_exiting(godot::Object *p_agent) {
	(void)remove_agent(godot::Object::cast_to<ScholaAgent>(p_agent));
}

godot::Error ScholaInferenceStepper::report(const godot::String &p_message, godot::Error p_error) {
	report_failure(p_message, p_error);
	emit_signal("inference_failed", p_message);
	return p_error;
}

godot::Error ScholaInferenceStepper::report(const godot::String &p_context, const schola::Status &p_status) {
	return report(p_context + godot::String(": ") + to_godot_string(p_status.get_message()), to_godot_error(p_status));
}

void ScholaInferenceStepper::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("set_policy", "policy"), &ScholaInferenceStepper::set_policy);
	godot::ClassDB::bind_method(godot::D_METHOD("get_policy"), &ScholaInferenceStepper::get_policy);
	godot::ClassDB::bind_method(godot::D_METHOD("set_agents", "agents"), &ScholaInferenceStepper::set_agents);
	godot::ClassDB::bind_method(godot::D_METHOD("get_agents"), &ScholaInferenceStepper::get_agents);
	godot::ClassDB::bind_method(godot::D_METHOD("set_enabled", "enabled"), &ScholaInferenceStepper::set_enabled);
	godot::ClassDB::bind_method(godot::D_METHOD("is_enabled"), &ScholaInferenceStepper::is_enabled);
	godot::ClassDB::bind_method(godot::D_METHOD("add_agent", "agent"), &ScholaInferenceStepper::add_agent);
	godot::ClassDB::bind_method(godot::D_METHOD("remove_agent", "agent"), &ScholaInferenceStepper::remove_agent);
	godot::ClassDB::bind_method(godot::D_METHOD("reset_state", "agent"), &ScholaInferenceStepper::reset_state);
	godot::ClassDB::bind_method(godot::D_METHOD("reset_states"), &ScholaInferenceStepper::reset_states);
	godot::ClassDB::bind_method(godot::D_METHOD("step"), &ScholaInferenceStepper::step);
	godot::ClassDB::bind_method(godot::D_METHOD("get_configuration_errors"), &ScholaInferenceStepper::get_configuration_errors);

	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::OBJECT, "policy", godot::PROPERTY_HINT_RESOURCE_TYPE, "ScholaOnnxPolicy"), "set_policy", "get_policy");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::ARRAY, "agents", godot::PROPERTY_HINT_TYPE_STRING,
						 godot::String::num_int64(godot::Variant::NODE_PATH) + "/" + godot::String::num_int64(godot::PROPERTY_HINT_NODE_PATH_VALID_TYPES) + ":ScholaAgent"),
			"set_agents", "get_agents");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_SIGNAL(godot::MethodInfo("inference_failed", godot::PropertyInfo(godot::Variant::STRING, "message")));
}
