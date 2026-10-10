// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/lifecycle/environment_lifecycle.h"

#include <memory>
#include <vector>

namespace schola {

// Coordinates a fixed, ordered set of lifecycle instances and owns them. Python
// owns space and point validation. The coordinator performs only the checks
// needed to route operations safely and enforce its lifecycle. If an operation
// fails after an environment mutates, the failure is returned to the connector
// for reporting to Python. Output parameters remain unchanged whenever an
// operation returns a non-OK Status.
class EnvironmentCoordinator {
public:
	EnvironmentCoordinator() = default;

	EnvironmentCoordinator(const EnvironmentCoordinator &) = delete;
	EnvironmentCoordinator &operator=(const EnvironmentCoordinator &) = delete;

	// Each lifecycle ID must equal its position in the vector. Registration is
	// fixed after define() succeeds. Ownership transfers to the coordinator only
	// when registration succeeds; on failure, p_lifecycles remains unchanged.
	Status set_lifecycles(std::vector<std::unique_ptr<EnvironmentLifecycle>> &&p_lifecycles);

	// May be called exactly once before define(), reset(), or step(), matching
	// StartGymConnector's position in the existing Python protocol sequence.
	Status set_autoreset_mode(AutoResetMode p_mode);

	// Initializes every lifecycle after the autoreset mode is set and returns
	// definitions in EnvironmentId order. The output is changed only when every
	// lifecycle initializes successfully.
	Status define(TrainingDefinition &r_definition);

	// Explicit reset may interrupt ACTIVE environments and resets every registered
	// environment. An omitted request entry supplies default ResetSettings,
	// matching a Python reset request with no seed or options.
	Status reset(const ResetRequest &p_request, InitialState &r_initial_state);

	// Routes actions without validating their contents. A completed environment
	// under DISABLED mode retains its final state and is not stepped. SAME_STEP
	// preserves terminal state and returns reset observations separately. Under
	// NEXT_STEP, a completed environment resets instead of consuming its action
	// map and returns its initial observation with zero reward and false completion
	// flags. Physical effects may appear in a later observation according to
	// Godot's normal frame timing.
	Status step(const StepRequest &p_request, StepResult &r_result);

	// Closes every lifecycle and rejects future operations. Repeated calls are
	// successful and have no additional effect.
	Status close();

private:
	std::vector<std::unique_ptr<EnvironmentLifecycle>> environments;
	AutoResetMode autoreset_mode = AutoResetMode::DISABLED;
	bool mode_set = false;
};

} // namespace schola
