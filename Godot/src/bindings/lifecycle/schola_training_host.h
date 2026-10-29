// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/lifecycle/environment_coordinator.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/object_id.hpp>

#include <optional>
#include <vector>

class ScholaEnvironment;

class ScholaTrainingHost : public godot::Node {
	GDCLASS(ScholaTrainingHost, godot::Node)

public:
	// Discovers and validates the current scene's trainable environments. Their
	// depth-first scene-tree order remains fixed for this session.
	schola::Status initialize_session();

	// Call environment coordinator
	schola::Status set_autoreset_mode(schola::AutoResetMode p_mode);
	schola::Status define(schola::TrainingDefinition &r_definition);
	schola::Status reset(const schola::ResetRequest &p_request, schola::InitialState &r_initial_state);
	schola::Status step(const schola::StepRequest &p_request, schola::StepResult &r_result);
	schola::Status close();

protected:
	static void _bind_methods();

private:
	std::vector<godot::ObjectID> environment_ids;
	schola::EnvironmentCoordinator coordinator;
	std::optional<schola::TrainingDefinition> training_definition;
	bool session_initialized = false;
};
