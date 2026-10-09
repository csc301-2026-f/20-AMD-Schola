// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/types.h"
#include "core/lifecycle/training_types.h"

#include "core/common/status.h"

namespace schola {

// Enforces legal state transitions for one non-owned environment. This is the
// only US4 class that directly depends on the provisional US1 Environment API.
// US1 must let this class initialize definitions, reset with settings, and step
// the environment. Environment membership and definitions remain fixed after
// initialize(). Output parameters remain unchanged whenever an operation returns
// a non-OK Status.
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

	// Starts a new episode and transitions to ACTIVE. Reset is allowed from
	// RESET_PENDING, ACTIVE, or COMPLETE, so an explicit request may interrupt an
	// active episode. The output is changed only when the reset succeeds. The
	// initial observation is forwarded without an engine-side value scan; Python
	// owns observation-space validation.
	Status reset(const ResetSettings &p_settings, InitialEnvironmentState &r_initial_state);

	// Requires ACTIVE. Steps unfinished agents and captures an owned state
	// snapshot. Physical effects may appear in a later observation according to
	// Godot's normal frame timing. The environment transitions to COMPLETE when
	// every agent is terminated or truncated; otherwise it remains ACTIVE. Point
	// contents are forwarded without an engine-side value scan; Python owns space
	// validation. The output is changed only when the step succeeds.
	Status step(const std::map<AgentId, Point> &p_actions, EnvironmentState &r_state);

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
