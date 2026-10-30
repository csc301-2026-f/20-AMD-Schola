// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/lifecycle/schola_training_host.h"

#include "bindings/environment/schola_environment.h"

#include "interop/variant_conversion.h"

#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/thread.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstdint>
#include <memory>
#include <utility>
#include <vector>

namespace {

void collect_environments(godot::Node *p_node, std::vector<ScholaEnvironment *> &r_environments) {
	if (p_node == nullptr) {
		return;
	}

	auto *environment = godot::Object::cast_to<ScholaEnvironment>(p_node);
	if (environment != nullptr) {
		r_environments.push_back(environment);
	}

	for (int64_t i = 0; i < p_node->get_child_count(); ++i) {
		collect_environments(p_node->get_child(i), r_environments);
	}
}

godot::Dictionary encode_status(const schola::Status &status) {
	godot::Dictionary dict;
	dict["code"] = static_cast<int>(status.get_code());
	dict["message"] = godot::String(status.get_message().c_str());
	return dict;
}

godot::Dictionary encode_training_definition(const schola::TrainingDefinition &defn) {
	godot::Array environments;
	for (auto &environment : defn.environments) {
		godot::Dictionary agents;
		for (auto &[agent_id, definition] : environment.agents) {
			godot::Dictionary encoded_definition;
			encoded_definition["observation_space"] = schola::space_to_variant(definition.observation_space);
			encoded_definition["action_space"] = schola::space_to_variant(definition.action_space);
			encoded_definition["agent_type"] = godot::String::utf8(definition.agent_type.c_str());
			agents[godot::String::utf8(agent_id.c_str())] = encoded_definition;
		}

		godot::Dictionary encoded_environment;
		encoded_environment["agents"] = agents;
		environments.append(encoded_environment);
	}

	godot::Dictionary result;
	result["environments"] = environments;
	return result;
}

schola::Status decode_step_request(const godot::Dictionary &dict,
	schola::TrainingDefinition &definition, schola::StepRequest &r_request) {

	if (!dict.has("actions") || dict["actions"].get_type() != godot::Variant::ARRAY) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
				"step request actions must be an array");
	}

	godot::Array actions = dict["actions"];
	if (actions.size() != static_cast<int64_t>(definition.environments.size())) {
		return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
				"step request must contain one action map per environment");
	}

	schola::StepRequest request;
	request.actions.reserve(actions.size());
	for (int64_t environment_index = 0; environment_index < actions.size(); ++environment_index) {
		if (actions[environment_index].get_type() != godot::Variant::DICTIONARY) {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
					"each environment action entry must be a dictionary");
		}

		godot::Dictionary environment_actions = actions[environment_index];
		schola::EnvironmentDefinition &environment_definition = definition.environments[environment_index];
		std::map<schola::AgentId, schola::Point> decoded_actions;

		godot::Array agent_ids = environment_actions.keys();
		for (int64_t agent_index = 0; agent_index < agent_ids.size(); ++agent_index) {
			godot::Variant agent_id_value = agent_ids[agent_index];
			if (agent_id_value.get_type() != godot::Variant::STRING) {
				return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
						"step request agent IDs must be strings");
			}

			schola::AgentId agent_id = godot::String(agent_id_value).utf8().get_data();
			auto agent_definition = environment_definition.agents.find(agent_id);
			if (agent_definition == environment_definition.agents.end()) {
				return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
						"step request contains an unknown agent ID");
			}

			schola::Point point;
			schola::Status status = schola::variant_to_point(
					environment_actions[agent_id_value],
					agent_definition->second.action_space,
					point);

			if (!status.is_ok()) {
				return status;
			}
			decoded_actions.emplace(agent_id, std::move(point));
		}

		request.actions.push_back(std::move(decoded_actions));
	}

	r_request = std::move(request);
	return schola::Status::ok();
}

schola::ResetRequest decode_reset_request(const godot::Dictionary &dict) {
	schola::ResetRequest request;

	godot::Array keys = dict.keys();

	for (int i = 0; i < keys.size(); ++i) {
		int environment_id = keys[i];
		godot::Dictionary entry = dict[environment_id];
		schola::ResetSettings settings;

		if (entry.has("seed")) {
			settings.seed = static_cast<int>(entry["seed"]);
		}

		if (entry.has("options")) {
			godot::Dictionary options = entry["options"];
			for (int j = 0; j < options.keys().size(); j++) {
				std::string key = godot::String(options.keys()[j]).utf8().get_data();
				std::string value = godot::String(options.values()[j]).utf8().get_data();
				settings.options[key] = value;
			}
		}

		request.environments[environment_id] = std::move(settings);
	}
	return request;
}

godot::Dictionary encode_info(const std::map<std::string, std::string> &info) {
	godot::Dictionary result;
	for (auto &[key, value] : info) {
		result[godot::String::utf8(key.c_str())] = godot::String::utf8(value.c_str());
	}
	return result;
}

godot::Dictionary encode_initial_state(const schola::InitialState &state) {
	godot::Dictionary environments;
	for (auto &[environment_id, environment] : state.environments) {
		godot::Dictionary agents;
		for (auto &[agent_id, agent] : environment.agents) {
			godot::Dictionary encoded_agent;
			encoded_agent["observation"] = schola::point_to_variant(agent.observation);
			encoded_agent["info"] = encode_info(agent.info);
			agents[godot::String::utf8(agent_id.c_str())] = encoded_agent;
		}
		environments[environment_id] = agents;
	}
	return environments;
}

godot::Dictionary encode_step_result(const schola::StepResult &result) {
	godot::Array environments;
	for (auto &environment : result.state.environments) {
		godot::Dictionary agents;
		for (auto &[agent_id, agent] : environment.agents) {
			godot::Dictionary encoded_agent;
			encoded_agent["observation"] = schola::point_to_variant(agent.observation);
			encoded_agent["reward"] = agent.reward;
			encoded_agent["terminated"] = agent.terminated;
			encoded_agent["truncated"] = agent.truncated;
			encoded_agent["info"] = encode_info(agent.info);
			agents[godot::String::utf8(agent_id.c_str())] = encoded_agent;
		}
		environments.append(agents);
	}

	godot::Dictionary encoded;
	encoded["state"] = environments;
	encoded["initial_state"] = encode_initial_state(result.initial_state);
	return encoded;
}

godot::Dictionary encode_result(const schola::Status &status,
		const godot::Variant &value = godot::Variant()) {
	godot::Dictionary result;
	result["status"] = encode_status(status);
	result["value"] = value;
	return result;
}

} // namespace

schola::Status ScholaTrainingHost::initialize_session_core() {
	if (session_state != SessionState::CONFIGURING) {
		const char *message = session_state == SessionState::ACTIVE ?
				"training session is already initialized" :
				"training session is shutting down or closed";
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION, message);
	}

	godot::SceneTree *tree = get_tree();
	if (tree == nullptr) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"training host is not inside a scene tree");
	}

	godot::Node *scene_root = tree->get_current_scene();
	if (scene_root == nullptr) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"scene tree has no current scene");
	}

	std::vector<ScholaEnvironment *> discovered_environments;
	collect_environments(scene_root, discovered_environments);
	if (discovered_environments.empty()) {
		return schola::Status::error(schola::StatusCode::NOT_FOUND,
				"current scene contains no ScholaEnvironment nodes");
	}

	std::vector<godot::ObjectID> discovered_ids;
	std::vector<std::unique_ptr<schola::EnvironmentLifecycle>> lifecycles;
	discovered_ids.reserve(discovered_environments.size());
	lifecycles.reserve(discovered_environments.size());

	for (size_t i = 0; i < discovered_environments.size(); ++i) {
		ScholaEnvironment *environment_node = discovered_environments[i];
		if (!environment_node->get_configuration_errors().is_empty()) {
			return schola::Status::error(schola::StatusCode::INVALID_DATA,
					"a discovered ScholaEnvironment has configuration errors");
		}

		schola::Environment *environment = environment_node->get_environment();
		if (environment == nullptr) {
			return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
					"a discovered ScholaEnvironment has no core environment adapter");
		}

		int32_t step_limit = environment_node->get_max_episode_steps();
		if (step_limit < 0) {
			return schola::Status::error(schola::StatusCode::INVALID_DATA,
					"a discovered ScholaEnvironment has a negative step limit");
		}

		discovered_ids.emplace_back(environment_node->get_instance_id());
		lifecycles.push_back(std::make_unique<schola::EnvironmentLifecycle>(
				static_cast<schola::EnvironmentId>(i),
				*environment,
				static_cast<uint64_t>(step_limit)));
	}

	schola::Status result = coordinator.set_lifecycles(std::move(lifecycles));
	if (!result.is_ok()) {
		return result;
	}

	environment_ids = std::move(discovered_ids);
	session_state = SessionState::ACTIVE;
	return schola::Status::ok();
}

schola::Status ScholaTrainingHost::require_active_session() const {
	if (session_state == SessionState::ACTIVE) {
		return schola::Status::ok();
	}

	const char *message = session_state == SessionState::CONFIGURING ?
			"training session is not initialized" :
			"training session is shutting down or closed";
	return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION, message);
}

schola::Status ScholaTrainingHost::require_main_thread() {
	if (godot::Thread::is_main_thread()) {
		return schola::Status::ok();
	}

	return schola::Status::error(
			schola::StatusCode::FAILED_PRECONDITION,
			"ScholaTrainingHost operations must run on the Godot main thread");
}

schola::Status ScholaTrainingHost::shutdown_core() {
	if (session_state == SessionState::CLOSED || session_state == SessionState::SHUTTING_DOWN) {
		return schola::Status::ok();
	}

	session_state = SessionState::SHUTTING_DOWN;
	schola::Status status = coordinator.close();
	training_definition.reset();
	environment_ids.clear();
	session_state = SessionState::CLOSED;
	return status;
}

godot::Dictionary ScholaTrainingHost::initialize_session() {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	return encode_result(initialize_session_core());
}

godot::Dictionary ScholaTrainingHost::set_autoreset_mode(int64_t p_mode) {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	schola::Status active = require_active_session();
	if (!active.is_ok()) {
		return encode_result(active);
	}

	return encode_result(coordinator.set_autoreset_mode(
			static_cast<schola::AutoResetMode>(p_mode)));
}

godot::Dictionary ScholaTrainingHost::define() {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	schola::Status active = require_active_session();
	if (!active.is_ok()) {
		return encode_result(active);
	}

	schola::TrainingDefinition definition;
	schola::Status status = coordinator.define(definition);
	if (!status.is_ok()) {
		return encode_result(status);
	}

	training_definition = definition;
	return encode_result(status, encode_training_definition(definition));
}

godot::Dictionary ScholaTrainingHost::reset(const godot::Dictionary &p_request) {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	schola::Status active = require_active_session();
	if (!active.is_ok()) {
		return encode_result(active);
	}

	schola::InitialState state;
	schola::Status status = coordinator.reset(decode_reset_request(p_request), state);
	return status.is_ok() ? encode_result(status, encode_initial_state(state)) : encode_result(status);
}

godot::Dictionary ScholaTrainingHost::step(const godot::Dictionary &p_request) {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	schola::Status active = require_active_session();
	if (!active.is_ok()) {
		return encode_result(active);
	}

	if (!training_definition.has_value()) {
		return encode_result(schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"training session is not defined"));
	}

	schola::StepRequest request;
	schola::Status status = decode_step_request(p_request, *training_definition, request);
	if (!status.is_ok()) {
		return encode_result(status);
	}

	schola::StepResult result;
	status = coordinator.step(request, result);
	return status.is_ok() ? encode_result(status, encode_step_result(result)) : encode_result(status);
}

godot::Dictionary ScholaTrainingHost::close() {
	schola::Status thread_status = require_main_thread();
	if (!thread_status.is_ok()) {
		return encode_result(thread_status);
	}

	return encode_result(shutdown_core());
}

void ScholaTrainingHost::_exit_tree() {
	schola::Status status = shutdown_core();
	if (!status.is_ok()) {
		godot::UtilityFunctions::push_error(
				godot::String("ScholaTrainingHost shutdown failed: ") + status.get_message().c_str());
	}
}

void ScholaTrainingHost::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("initialize_session"), &ScholaTrainingHost::initialize_session);
	godot::ClassDB::bind_method(godot::D_METHOD("set_autoreset_mode", "mode"), &ScholaTrainingHost::set_autoreset_mode);
	godot::ClassDB::bind_method(godot::D_METHOD("define"), &ScholaTrainingHost::define);
	godot::ClassDB::bind_method(godot::D_METHOD("reset", "request"), &ScholaTrainingHost::reset);
	godot::ClassDB::bind_method(godot::D_METHOD("step", "request"), &ScholaTrainingHost::step);
	godot::ClassDB::bind_method(godot::D_METHOD("close"), &ScholaTrainingHost::close);
}
