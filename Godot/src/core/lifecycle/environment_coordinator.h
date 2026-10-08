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
	// fixed after define() succeeds. Ownership transfers to the coordinator only
	// when registration succeeds; on failure, p_lifecycles remains unchanged.
	Status set_lifecycles(std::vector<std::unique_ptr<EnvironmentLifecycle>> &&p_lifecycles);

	// Initializes every lifecycle and returns definitions in EnvironmentId order.
	// The output is changed only when every lifecycle initializes successfully.
	Status define(TrainingDefinition &r_definition);

	// May be called exactly once after define() and before reset() or begin_step().
	Status set_autoreset_mode(AutoResetMode p_mode);

	// Validates every requested ID and setting before resetting any environment.
	// Explicit reset may interrupt an ACTIVE environment. Environments omitted
	// from the request are unchanged.
	Status reset(const ResetRequest &p_request, InitialState &r_initial_state);

	// begin_step validates the complete batch before applying any actions and
	// handles environments due for NEXT_STEP reset. The host must cross exactly
	// one physics boundary before calling finish_step. A completed environment
	// under DISABLED mode retains its final state and is not stepped. Under
	// NEXT_STEP it resets here instead of consuming its action map; that map may
	// be empty and is otherwise ignored. Only one step may be pending.
	Status begin_step(const StepRequest &p_request);

	// finish_step collects owned snapshots and performs SAME_STEP resets without
	// overwriting terminal states. SAME_STEP reset observations are returned in
	// r_initial_state. For NEXT_STEP, an environment reset by begin_step appears
	// only in r_state with its initial observation, zero reward, and false
	// termination and truncation flags.
	Status finish_step(TrainingState &r_state, InitialState &r_initial_state);

	// Closes every lifecycle and rejects future operations. Repeated calls are
	// successful and have no additional effect.
	Status close();

private:
	std::vector<std::unique_ptr<EnvironmentLifecycle>> environments;
	AutoResetMode autoreset_mode = AutoResetMode::DISABLED;
	bool mode_set = false;
	bool step_pending = false;
};

} // namespace schola
