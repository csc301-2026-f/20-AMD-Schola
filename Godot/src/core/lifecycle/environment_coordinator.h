// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/lifecycle/environment_lifecycle.h"

#include <memory>
#include <vector>

namespace schola {

/**
 * Owns and coordinates a fixed, EnvironmentId-ordered set of lifecycles.
 *
 * The coordinator routes operations and applies AutoResetMode without validating
 * point contents. Output parameters remain unchanged when an operation returns a
 * non-OK Status. If an operation fails after an environment may have mutated,
 * the entire coordinator becomes FAULTED; partial rollback and recovery are not
 * attempted. A faulted coordinator accepts only close().
 */
class EnvironmentCoordinator {
public:
	EnvironmentCoordinator() = default;

	EnvironmentCoordinator(const EnvironmentCoordinator &) = delete;
	EnvironmentCoordinator &operator=(const EnvironmentCoordinator &) = delete;

	CoordinatorState get_state() const;

	/**
	 * Registers a nonempty collection of uninitialized lifecycles.
	 *
	 * Each lifecycle ID must equal its vector position. Ownership transfers only
	 * on success, and registration is accepted only while CONFIGURING.
	 */
	Status set_lifecycles(std::vector<std::unique_ptr<EnvironmentLifecycle>> &&p_lifecycles);

	/** Configures autoreset exactly once while CONFIGURING and before define(). */
	Status set_autoreset_mode(AutoResetMode p_mode);

	/**
	 * Initializes every lifecycle and returns definitions in EnvironmentId order.
	 * Requires CONFIGURING and an autoreset mode. Success transitions to READY.
	 */
	Status define(TrainingDefinition &r_definition);

	/**
	 * Resets every environment and transitions to RUNNING.
	 *
	 * Requires READY or RUNNING. Missing request entries use default ResetSettings;
	 * unknown environment IDs are rejected before any environment is called.
	 */
	Status reset(const ResetRequest &p_request, InitialState &r_initial_state);

	/**
	 * Routes one action map per environment and applies the configured autoreset.
	 *
	 * Requires RUNNING. DISABLED retains completed states. SAME_STEP returns the
	 * terminal state and separate reset observations in the same result. NEXT_STEP
	 * resets a completed environment on the following call instead of consuming
	 * its actions. Automatic resets use default ResetSettings.
	 */
	Status step(const StepRequest &p_request, StepResult &r_result);

	/** Closes every lifecycle and idempotently transitions to CLOSED. */
	Status close();

private:
	std::vector<std::unique_ptr<EnvironmentLifecycle>> environments;
	// Retains final snapshots for completed environments in DISABLED mode.
	TrainingState last_state;
	AutoResetMode autoreset_mode = AutoResetMode::DISABLED;
	CoordinatorState state = CoordinatorState::CONFIGURING;
	bool mode_set = false;
};

} // namespace schola
