// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/lifecycle/schola_training_host.h"

#include "bindings/environment/schola_environment.h"

#include "interop/variant_conversion.h"

#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/core/object.hpp>

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

schola::Status decode_status(const godot::Dictionary &dict) {
	auto code = static_cast<schola::StatusCode>(static_cast<int>(dict["code"]));
	std::string message = godot::String(dict["message"]).utf8().get_data();

	if (code == schola::StatusCode::OK) {
		return schola::Status::ok();
	}
	return schola::Status::error(code, message);
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

godot::Dictionary encode_step_request(const schola::StepRequest &request) {
	godot::Array arr;

	for (auto &environment_actions : request.actions) {
		godot::Dictionary dict;
		for (auto &[agent_id, point] : environment_actions) {
			godot::String converted_id = godot::String::utf8(agent_id.c_str());
			godot::Variant converted_point = schola::point_to_variant(point);
			dict[converted_id] = converted_point;
		}
		arr.append(dict);
	}

	godot::Dictionary result;
	result["actions"] = arr;
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

godot::Dictionary encode_reset_request(const schola::ResetRequest &request) {
	godot::Dictionary dict;

	for (auto &[env_id, reset_settings] : request.environments) {
		godot::Dictionary entry;

		if (reset_settings.seed.has_value()) {
			entry["seed"] = reset_settings.seed.value();
		}

		godot::Dictionary options;
		for (auto &[k, v] : reset_settings.options) {
			auto key = godot::String::utf8(k.c_str());
			auto value = godot::String::utf8(v.c_str());
			options[key] = value;
		}
		entry["options"] = options;

		dict[env_id] = entry;
	}
	return dict;
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

} // namespace

schola::Status ScholaTrainingHost::initialize_session() {
	if (session_initialized) {
		return schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"training session is already initialized");
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
	session_initialized = true;
	return schola::Status::ok();
}

schola::Status ScholaTrainingHost::set_autoreset_mode(schola::AutoResetMode p_mode) {
	return coordinator.set_autoreset_mode(p_mode);
}

schola::Status ScholaTrainingHost::define(schola::TrainingDefinition &r_definition) {
	schola::TrainingDefinition definition;
	schola::Status status = coordinator.define(definition);
	if (!status.is_ok()) {
		return status;
	}

	training_definition = definition;
	r_definition = std::move(definition);
	return schola::Status::ok();
}

schola::Status ScholaTrainingHost::reset(const schola::ResetRequest &p_request,
	schola::InitialState &r_initial_state) {
	return coordinator.reset(p_request, r_initial_state);
}

schola::Status ScholaTrainingHost::step(const schola::StepRequest &p_request,
	schola::StepResult &r_result) {
	return coordinator.step(p_request, r_result);
}

schola::Status ScholaTrainingHost::close() {
	schola::Status status = coordinator.close();
	training_definition.reset();
	return status;
}

void ScholaTrainingHost::_bind_methods() {
}
