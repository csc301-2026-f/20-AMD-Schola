// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/training/schola_training_host.h"

#include "bindings/environment/schola_environment.h"

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

	ScholaEnvironment *environment = godot::Object::cast_to<ScholaEnvironment>(p_node);
	if (environment != nullptr) {
		r_environments.push_back(environment);
	}

	for (int64_t i = 0; i < p_node->get_child_count(); ++i) {
		collect_environments(p_node->get_child(i), r_environments);
	}
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

		const int32_t step_limit = environment_node->get_max_episode_steps();
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

void ScholaTrainingHost::_bind_methods() {
}
