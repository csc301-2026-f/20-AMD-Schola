// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/policy/policy.h"
#include "core/policy/policy_state.h"
#include "core/spaces/point.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace schola::testing {

class CounterState final : public PolicyState {
public:
	int32_t count = 0;

	void reset() override { count = 0; }
	Status copy_from(const PolicyState &p_other) override;
	std::string to_string() const override { return "CounterState(" + std::to_string(count) + ")"; }
};

class FakePolicy final : public Policy {
public:
	Point action;
	bool stateful = false;
	std::vector<Point> observations;
	std::vector<const PolicyState *> states;
	int32_t fail_at_call = -1;
	Status failure = Status::error(StatusCode::RUNTIME_FAILURE, "FakePolicy failure");

	Status init(const InteractionDefinition &p_definition) override;
	Status create_initial_state(std::unique_ptr<PolicyState> &r_state) const override;
	Status think(const Point &p_observation, PolicyState &p_state, Point &r_action) override;
};

} // namespace schola::testing
