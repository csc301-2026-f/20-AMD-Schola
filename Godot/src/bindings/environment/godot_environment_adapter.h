// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/environment/environment.h"
#include "core/spaces/space.h"

#include <godot_cpp/core/object_id.hpp>

#include <cstdint>
#include <map>
#include <vector>

class ScholaEnvironment;

/**
 * Lets the training lifecycle (US4) use a ScholaEnvironment node as a
 * schola::Environment.
 *
 * Each agent below the node is reached through its own GodotAgentAdapter
 * (ScholaAgent::get_agent()). This class adds the environment's hooks on
 * top: _reset_episode, _get_reward, _is_terminated, _is_truncated and
 * _get_info.
 *
 * Training only. The ScholaEnvironment node creates and owns this adapter,
 * so the node always outlives it. Main thread only. Every failure leaves
 * the output untouched.
 */
class GodotEnvironmentAdapter final : public schola::Environment {
public:
	/**
	 * Wraps a ScholaEnvironment node.
	 *
	 * @param p_node The node this adapter answers for. Not owned; the node
	 *        creates and owns this adapter, so it always outlives it.
	 */
	explicit GodotEnvironmentAdapter(ScholaEnvironment *p_node);

	/**
	 * Finds the agents below the node and asks each one to define() itself.
	 *
	 * Agent IDs come from each ScholaAgent's agent_id. The agent set is
	 * fixed once this succeeds.
	 *
	 * @param r_agents Filled with one InteractionDefinition per agent, keyed
	 *        by agent ID. Untouched on failure.
	 * @return OK on success.
	 *         FAILED_PRECONDITION if this was already called, there are no
	 *         agents, the node reports a configuration error, or two agents
	 *         share an ID.
	 *         Any error from an agent's define(), such as an unset or
	 *         invalid space, passed through unchanged.
	 */
	schola::Status initialize(std::map<schola::AgentId, schola::InteractionDefinition> &r_agents) override;

	/**
	 * Starts an episode.
	 *
	 * Seeds the node's get_rng() when p_settings has a seed and otherwise
	 * lets it keep running, calls _reset_episode(seed, options), then
	 * observes every agent. Overriding _reset_episode is optional. Every
	 * agent counts as unfinished again. Emits episode_started on the node.
	 *
	 * @param p_settings This episode's seed and options. The seed reaches
	 *        _reset_episode as an int, or null when unset.
	 * @param r_states Filled with one InitialAgentState per agent, keyed by
	 *        agent ID. Untouched on failure.
	 * @return OK on success.
	 *         FAILED_PRECONDITION before initialize(), if a seed was given
	 *         but get_rng() returns null, or if an agent node was freed.
	 *         Any error from an agent's observe(), passed through unchanged.
	 *         After a failure, step() refuses to run until a reset succeeds.
	 */
	schola::Status reset(const schola::ResetSettings &p_settings,
			std::map<schola::AgentId, schola::InitialAgentState> &r_states) override;

	/**
	 * Runs one logical step in two phases, so a bad action moves nobody.
	 *
	 * 1. Checks every action and that _get_reward is overridden, before any
	 *    agent moves.
	 * 2. Every agent with an action calls act(), in scene-tree order. Then
	 *    each of them calls observe(), followed by _get_reward,
	 *    _is_terminated, _is_truncated and _get_info.
	 *
	 * _get_reward must be overridden; the others default to false and an
	 * empty Dictionary. The step limit belongs to US4, so max_episode_steps
	 * is not applied here. Emits episode_ended once every agent has
	 * finished.
	 *
	 * @param p_actions One action per agent that should act this step, keyed
	 *        by agent ID. A finished agent is left out, not an error.
	 * @param r_states Filled with one AgentState per agent in p_actions,
	 *        keyed by agent ID. Untouched on failure.
	 * @return OK on success.
	 *         Phase 1, nothing has moved:
	 *         NOT_FOUND for an unknown agent.
	 *         FAILED_PRECONDITION before reset(), for an agent that already
	 *         finished, for a freed agent node, or if _get_reward is not
	 *         overridden.
	 *         INVALID_ARGUMENT for an action outside its action space.
	 *         Phase 2, the world may already have changed, so the caller
	 *         should end the session:
	 *         any error from act() or observe(), FAILED_PRECONDITION if
	 *         _get_reward could not be called, or INVALID_ARGUMENT if
	 *         _get_info returns a non-String key or value.
	 */
	schola::Status step(const std::map<schola::AgentId, schola::Point> &p_actions,
			std::map<schola::AgentId, schola::AgentState> &r_states) override;

	/**
	 * Hands out each agent's GodotAgentAdapter, for callers that only need
	 * observe() and act().
	 *
	 * @param r_agents Filled with non-owning pointers, in scene-tree order.
	 *        Each stays valid only while its agent node exists. Untouched on
	 *        failure.
	 * @return OK on success.
	 *         FAILED_PRECONDITION before initialize() or if an agent node
	 *         was freed.
	 */
	schola::Status get_agents(std::vector<schola::Agent *> &r_agents) const override;

	/**
	 * Counts the steps that succeeded since the last successful reset().
	 *
	 * @return 0 before the first reset(), otherwise the number of step()
	 *         calls that returned OK since then.
	 */
	int64_t get_episode_step() const;

private:
	// What initialize() records about one agent.
	struct AgentEntry {
		schola::AgentId id;

		// Godot owns agent nodes and can free one at any time, so each call
		// looks the node up by ID instead of keeping a pointer that could
		// dangle. A freed agent fails the call with FAILED_PRECONDITION.
		godot::ObjectID node_id;

		// Cached so step() can check every action before any agent moves.
		schola::Space action_space;

		// Terminated or truncated this episode; cleared by reset().
		bool finished = false;
	};

	ScholaEnvironment *node = nullptr; // Not owned.
	std::vector<AgentEntry> agents; // Scene-tree order.
	bool initialized = false;
	bool episode_active = false;
	int64_t episode_step = 0;
};
