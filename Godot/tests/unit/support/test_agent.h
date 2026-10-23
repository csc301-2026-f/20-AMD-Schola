// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/environment/agent.h"
#include "core/environment/interaction_definition.h"
#include "core/spaces/point.h"

#include <cstdint>
#include <vector>

namespace schola::testing {

class FakeAgent final : public Agent {
public:
	InteractionDefinition definition;
	Point observation;
	std::vector<Point> actions;
	std::vector<Point> received_observations;
	Status define_result = Status::ok();
	Status observe_result = Status::ok();
	Status act_result = Status::ok();

	Status define(InteractionDefinition &r_definition) override;
	Status observe(Point &r_observation) override;
	Status act(const Point &p_action) override;
};

} // namespace schola::testing
