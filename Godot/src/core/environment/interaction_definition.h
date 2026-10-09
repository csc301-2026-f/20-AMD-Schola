// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/spaces/space.h"

#include <string>

namespace schola {

// The spaces one agent observes and acts in. Fixed after the agent is defined.
struct InteractionDefinition {
	Space observation_space;
	Space action_space;
	// Optional. Agents with the same type may share one policy in training; empty means the agent ID.
	std::string agent_type;
};

} // namespace schola
