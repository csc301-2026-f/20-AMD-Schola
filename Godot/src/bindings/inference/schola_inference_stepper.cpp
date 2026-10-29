// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/inference/schola_inference_stepper.h"

#include "bindings/environment/schola_agent.h"
#include "core/stepper/simple_stepper.h"
#include "inference/onnx_policy.h"
#include "interop/godot_status.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

ScholaInferenceStepper::ScholaInferenceStepper() = default;

ScholaInferenceStepper::~ScholaInferenceStepper() = default;

void ScholaInferenceStepper::set_policy(const godot::Ref<ScholaOnnxPolicy> &p_policy) {
	policy = p_policy;
	stepper.reset();
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
	godot::Error error = prepare(p_agent);
	if (error != godot::OK) {
		return error;
	}
	int32_t index = -1;
	schola::Status status = stepper->add_agent(p_agent->get_agent(), index);
	if (!status.is_ok()) {
		report(to_godot_string(status.get_message()));
		return to_godot_error(status);
	}
	return godot::OK;
}

int32_t ScholaInferenceStepper::remove_agent(ScholaAgent *p_agent) {
	if (stepper == nullptr || p_agent == nullptr) {
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

bool ScholaInferenceStepper::step() {
	if (stepper == nullptr) {
		return true;
	}
	schola::Status status = stepper->step();
	if (!status.is_ok()) {
		report(to_godot_string(status.get_message()));
		return false;
	}
	return true;
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
			report("ScholaInferenceStepper: '" + godot::String(path) + "' is not a ScholaAgent");
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
	if (p_agent == nullptr || p_agent->get_agent() == nullptr) {
		report("ScholaInferenceStepper.add_agent: the agent must be a ScholaAgent inside the scene tree");
		return godot::ERR_INVALID_PARAMETER;
	}
	if (policy.is_null()) {
		report("ScholaInferenceStepper: set a ScholaOnnxPolicy in the policy property");
		return godot::ERR_UNCONFIGURED;
	}
	godot::Error error = policy->is_loaded() ? godot::OK : policy->load();
	if (error == godot::OK && !policy->is_initialized()) {
		error = policy->initialize(p_agent);
	}
	if (error != godot::OK) {
		report("ScholaInferenceStepper: " + policy->get_last_error());
		return error;
	}
	if (stepper == nullptr) {
		stepper = std::make_unique<schola::SimpleStepper>();
		schola::Status status = stepper->init({}, policy->get_policy());
		if (!status.is_ok()) {
			stepper.reset();
			report(to_godot_string(status.get_message()));
			return to_godot_error(status);
		}
	}
	return godot::OK;
}

void ScholaInferenceStepper::report(const godot::String &p_message) {
	godot::UtilityFunctions::push_error(p_message);
	emit_signal("inference_failed", p_message);
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
