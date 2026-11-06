// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/types.h"
#include "core/lifecycle/training_types.h"

#include "core/common/status.h"

#include <cstdint>

namespace schola {

/**
 * @class EnvironmentLifecycle
 * @brief Coordinates one non-owned environment through its episode lifecycle.
 *
 * Environment membership and definitions remain fixed after initialize().
 * Output parameters remain unchanged when an operation returns a non-OK Status.
 * A validation failure detected before an Environment call leaves the lifecycle
 * state unchanged; a failed Environment call transitions it to FAULTED because
 * the caller cannot prove that the environment remained unchanged. A faulted
 * lifecycle accepts only close().
 *
 * Termination and truncation are reported by the Environment. The lifecycle
 * tracks successful steps but does not impose an episode-length limit.
 */
class EnvironmentLifecycle {
public:
	/**
	 * @brief Creates a lifecycle with a stable ID and a non-owning environment reference.
	 * @param[in] p_id Stable environment ID for this lifecycle.
	 * @param[in] p_environment Environment that this lifecycle coordinates.
	 */
	EnvironmentLifecycle(EnvironmentId p_id, Environment &p_environment);

	EnvironmentLifecycle(const EnvironmentLifecycle &) = delete;
	EnvironmentLifecycle &operator=(const EnvironmentLifecycle &) = delete;

	/** @return The stable environment ID assigned at construction. */
	EnvironmentId get_id() const;
	/** @return The lifecycle's current state. */
	LifecycleState get_state() const;
	/** @return The number of successful steps in the current episode. */
	uint64_t get_episode_step_count() const;
	/** @return The number of successfully started episodes. */
	uint64_t get_episode_count() const;

	/**
	 * @brief Returns the fixed definition discovered by a successful initialize().
	 * @return The environment definition, valid after initialize() succeeds.
	 */
	const EnvironmentDefinition &get_definition() const;

	/**
	 * @brief Discovers the environment definition and transitions from UNINITIALIZED to
	 * RESET_PENDING. Initialization may succeed only once.
	 * @return OK on success, or a failure describing the invalid state or environment error.
	 */
	Status initialize();

	/**
	 * @brief Starts a new episode and transitions to ACTIVE.
	 *
	 * Reset is allowed from RESET_PENDING, ACTIVE, or COMPLETE, so an explicit
	 * request may interrupt an active episode. Success increments the episode
	 * count and resets the step count to zero. The environment must return exactly
	 * the declared agent IDs. The output changes only on success.
	 * @param[in] p_settings Seed and options for this reset.
	 * @param[out] r_initial_state Initial state for every declared agent.
	 * @return OK on success, or a failure describing the invalid state, malformed output, or environment error.
	 */
	Status reset(const ResetSettings &p_settings, InitialEnvironmentState &r_initial_state);

	/**
	 * @brief Steps every unfinished agent and captures an owned state snapshot.
	 *
	 * Requires ACTIVE. Actions must name exactly the unfinished declared agents,
	 * and a successful response must name exactly the agents that acted. Each
	 * successful call increments the step count. The lifecycle becomes COMPLETE
	 * only when every agent is terminated or truncated by the environment.
	 * Otherwise it remains ACTIVE. The output changes only on success.
	 * @param[in] p_actions One action for every unfinished declared agent.
	 * @param[out] r_state Latest state for every agent in the environment.
	 * @return OK on success, or a failure describing invalid actions, malformed output, or an environment error.
	 */
	Status step(const std::map<AgentId, Point> &p_actions, EnvironmentState &r_state);

	/**
	 * @brief Releases episode-local state and idempotently transitions to CLOSED.
	 * @return OK after the lifecycle is closed.
	 */
	Status close();

private:
	EnvironmentId id;
	Environment &environment;
	LifecycleState state = LifecycleState::UNINITIALIZED;
	EnvironmentDefinition definition;
	EnvironmentState last_state;
	uint64_t episode_step_count = 0;
	uint64_t episode_num = 0;
};

} // namespace schola
