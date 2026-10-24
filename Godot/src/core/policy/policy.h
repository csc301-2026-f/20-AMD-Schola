// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/policy/policy_state.h"
#include "core/spaces/point.h"

#include <memory>
#include <vector>

namespace schola {

struct InteractionDefinition;

class Policy {
public:
	virtual ~Policy() = default;

	virtual Status init(const InteractionDefinition &p_definition) = 0;
	virtual Status create_initial_state(std::unique_ptr<PolicyState> &r_state) const;
	virtual Status think(const Point &p_observation, PolicyState &p_state, Point &r_action) = 0;
	virtual Status batched_think(const std::vector<const Point *> &p_observations, const std::vector<PolicyState *> &p_states, const std::vector<Point *> &r_actions);
	virtual bool is_recurrent() const { return false; }
	virtual bool is_busy() const { return false; }
};

} // namespace schola
