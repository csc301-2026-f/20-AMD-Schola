// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/types.h"
#include "core/lifecycle/training_types.h"

namespace schola {

// Enforces legal state transitions for one non-owned environment. This is the
// only US4 class that directly depends on the provisional US1 Environment API.
class EnvironmentLifecycle {
public:
	EnvironmentLifecycle(EnvironmentId p_id, Environment &p_environment);

	EnvironmentLifecycle(const EnvironmentLifecycle &) = delete;
	EnvironmentLifecycle &operator=(const EnvironmentLifecycle &) = delete;

	EnvironmentId get_id() const;
	LifecycleState get_state() const;

	// Valid after initialize() succeeds. The reference remains valid for the
	// lifetime of this lifecycle.
	const EnvironmentDefinition &get_definition() const;

	// Discovers the environment definition and transitions from UNINITIALIZED to
	// RESET_PENDING. Initialization may succeed only once.
	Status initialize();

	// Starts a new episode and transitions to ACTIVE. The output is changed only
	// when the reset succeeds.
	Status reset(const ResetSettings &p_settings,
		               InitialEnvironmentState &r_initial_state);

	// Requires ACTIVE. Validation is mutation-free, allowing a coordinator to
	// validate a complete batch before any environment advances.
	Status validate_step(const std::map<AgentId, Point> &p_actions) const;

	// Requires ACTIVE. Applies actions and transitions to STEP_PENDING.
	Status begin_step(const std::map<AgentId, Point> &p_actions);

	// Requires STEP_PENDING and must be called after one physics boundary.
	// Captures an owned snapshot and transitions to ACTIVE or COMPLETE. The
	// output is changed only when collection succeeds.
	Status finish_step(EnvironmentState &r_state);

	// Releases episode-local state and transitions to CLOSED. Closing an already
	// closed lifecycle succeeds without further work.
	Status close();

private:
	EnvironmentId id;
	Environment &environment;
	LifecycleState state = LifecycleState::UNINITIALIZED;
	EnvironmentDefinition definition;
	EnvironmentState last_state;
};

} // namespace schola
