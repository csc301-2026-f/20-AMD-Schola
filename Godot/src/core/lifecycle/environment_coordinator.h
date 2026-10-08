// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/lifecycle/environment_lifecycle.h"

#include <memory>
#include <vector>

namespace schola {

// Coordinates a fixed, ordered set of lifecycle instances and owns them.
class EnvironmentCoordinator {
public:
	EnvironmentCoordinator() = default;

	EnvironmentCoordinator(const EnvironmentCoordinator &) = delete;
	EnvironmentCoordinator &operator=(const EnvironmentCoordinator &) = delete;

	// Each lifecycle ID must equal its position in the vector. Registration is
	// fixed after define() succeeds.
	Status set_lifecycles(std::vector<std::unique_ptr<EnvironmentLifecycle>> p_lifecycles);

	Status define(TrainingDefinition &r_definition);

	Status set_autoreset_mode(AutoResetMode p_mode);

	Status reset(const ResetRequest &p_request, InitialState &r_initial_state);

	// begin_step validates the complete batch before applying any actions and
	// handles environments due for NEXT_STEP reset. The host must cross exactly
	// one physics boundary before calling finish_step. A completed environment
	// under DISABLED mode is not stepped; under NEXT_STEP it resets here instead
	// of consuming an action.
	Status begin_step(const StepRequest &p_request);

	// finish_step collects owned snapshots and performs SAME_STEP resets without
	// overwriting terminal states. Initial observations from those resets are
	// returned separately in r_initial_state.
	Status finish_step(TrainingState &r_state, InitialState &r_initial_state);

	Status close();

private:
	std::vector<std::unique_ptr<EnvironmentLifecycle>> environments;
	AutoResetMode autoreset_mode = AutoResetMode::DISABLED;
	bool mode_set = false;
	bool step_pending = false;
};

} // namespace schola
