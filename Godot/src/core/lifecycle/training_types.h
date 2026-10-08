// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/types.h"
#include "core/environment/environment.h"

#include <map>
#include <vector>

namespace schola {

enum class AutoResetMode {
	SAME_STEP,
	NEXT_STEP,
	DISABLED,
};

struct EnvironmentDefinition {
	std::map<AgentId, InteractionDefinition> agents;
};

struct TrainingDefinition {
	// Position in this vector is the EnvironmentId.
	std::vector<EnvironmentDefinition> environments;
};

struct StepRequest {
	// One action map per environment, ordered by EnvironmentId.
	// A resetting NEXT_STEP environment may have an empty map.
	std::vector<std::map<AgentId, Point>> actions;
};

struct ResetRequest {
	// Contains only environments explicitly requested to reset.
	std::map<EnvironmentId, ResetSettings> environments;
};

struct EnvironmentState {
	std::map<AgentId, AgentState> agents;
};

struct TrainingState {
	// One state per environment, ordered by EnvironmentId.
	std::vector<EnvironmentState> environments;
};

struct InitialEnvironmentState {
	std::map<AgentId, InitialAgentState> agents;
};

struct InitialState {
	// Contains only environments reset during this operation.
	std::map<EnvironmentId, InitialEnvironmentState> environments;
};

} // namespace schola
