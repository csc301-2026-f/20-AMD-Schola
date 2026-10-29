// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/lifecycle/environment_coordinator.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/object_id.hpp>

#include <vector>

class ScholaEnvironment;

class ScholaTrainingHost : public godot::Node {
	GDCLASS(ScholaTrainingHost, godot::Node)

public:
	// Discovers and validates the current scene's trainable environments. Their
	// depth-first scene-tree order remains fixed for this session.
	schola::Status initialize_session();

protected:
	static void _bind_methods();

private:
	std::vector<godot::ObjectID> environment_ids;
	schola::EnvironmentCoordinator coordinator;
	bool session_initialized = false;
};
