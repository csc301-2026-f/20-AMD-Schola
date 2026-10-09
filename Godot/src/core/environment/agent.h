// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/environment/interaction_definition.h"
#include "core/spaces/point.h"

namespace schola {

// One agent, used directly by inference (Unreal: IAgent). Training reaches agents through
// Environment, which also reports reward and done flags.
class Agent {
public:
	virtual ~Agent() = default;

	// Declares the agent's spaces. Called once before observe() or act(). Invalid or incomplete
	// configuration returns INVALID_ARGUMENT with a message listing every problem.
	virtual Status define(InteractionDefinition &r_definition) = 0;

	// Fills a point made by observation_space.make_point(). The point owns its data.
	virtual Status observe(Point &r_observation) = 0;

	// Applies one action that has already been validated against action_space.
	virtual Status act(const Point &p_action) = 0;
};

} // namespace schola
