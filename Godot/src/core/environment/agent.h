// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/environment/interaction_definition.h"

// Dependency on US4
#if !__has_include("core/common/status.h")
#error "US1 needs the shared Status type from core/common/status.h"
#endif

// Dependency on US2
#if !__has_include("core/spaces/point.h")
#error "US1 needs the Point type from core/spaces/point.h"
#endif

#include "core/common/status.h"
#include "core/spaces/point.h"

namespace schola {

/**
 * A trainable character in the game, such as an NPC or a car.
 *
 * An agent can do three things:
 * - Introduce itself with define()
 * - Look around with observe()
 * - Do something with act()
 *
 * Knows nothing about episodes, rewards, or Godot so that it can run with
 * training code stripped out, and be tested without the engine at all.
 *
 * Every method returns a Status and leaves its out-parameter untouched on
 * failure.
 *
 * This is a pure interface: every method below is left for a real class to
 * fill in (the Godot-facing adapter behind ScholaAgent, or a test fake). You
 * cannot create a bare Agent.
 */
class Agent {
public:
	// Required so deleting through an Agent* cleans up the real derived object
	virtual ~Agent() = default;

	/**
	 * Declares this agent's observation and action spaces.
	 *
	 * In:   r_definition, an empty InteractionDefinition.
	 *
	 * Does: fills in what this agent can see and what it can be told to do.
	 *       Called once, before any observe() or act().
	 *
	 * Out:  r_definition filled with this agent's observation_space,
	 *       action_space, and agent_type. The agent does not know its own
	 *       ID; the environment assigns IDs, as map keys.
	 */
	virtual Status define(InteractionDefinition &r_definition) = 0;

	/**
	 * Reads what the agent currently sees.
	 *
	 * In:   r_observation, a Point shaped to match observation_space (from
	 *       InteractionDefinition).
	 *
	 * Does: fills r_observation in place with what the agent currently sees.
	 *
	 * Out:  r_observation holds the real values. The Status says whether the
	 *       read succeeded; r_observation is untouched on failure.
	 */
	virtual Status observe(Point &r_observation) = 0;

	/**
	 * Applies one action.
	 *
	 * In:   p_action, a Point meant to match action_space. Python owns action
	 *       validation, and the engine re-checks only when US4's optional
	 *       debug validation is on, so act() must not trust the Point. A
	 *       mismatched Point returns a non-OK Status.
	 *
	 * Does: carries out that action on the agent. A rejected action leaves
	 *       the agent unchanged.
	 *
	 * Out:  a Status saying whether the action was applied.
	 */
	virtual Status act(const Point &p_action) = 0;
};

} // namespace schola
