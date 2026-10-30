// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/environment/environment.h"
#include "core/spaces/space.h"

#include <godot_cpp/core/object_id.hpp>

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
	// p_node is not owned.
	explicit GodotEnvironmentAdapter(ScholaEnvironment *p_node);

	/**
	 * Finds the agents below the node and asks each one to define() itself.
	 *
	 * Agent IDs come from each ScholaAgent's agent_id. Fails with
	 * FAILED_PRECONDITION if this was already called, there are no agents,
	 * or the node reports a configuration error such as a duplicate ID. The
	 * agent set is fixed once this succeeds.
	 */
	schola::Status initialize(std::map<schola::AgentId, schola::InteractionDefinition> &r_agents) override;

	/**
	 * Starts an episode.
	 *
	 * Seeds the node's get_rng() when p_settings has a seed and otherwise
	 * lets it keep running, calls _reset_episode(seed, options), then
	 * observes every agent. Emits episode_started on the node. Fails with
	 * FAILED_PRECONDITION before initialize().
	 */
	schola::Status reset(const schola::ResetSettings &p_settings,
			std::map<schola::AgentId, schola::InitialAgentState> &r_states) override;

	/**
	 * Runs one logical step in two phases, so a bad action moves nobody.
	 *
	 * 1. Checks every action first: NOT_FOUND for an unknown agent,
	 *    FAILED_PRECONDITION for one that already finished or before
	 *    reset(), INVALID_ARGUMENT for one outside its action space.
	 * 2. For each agent with an action: act(), observe(), then
	 *    _get_reward, _is_terminated, _is_truncated and _get_info.
	 *
	 * _get_reward must be overridden; the others default to false and an
	 * empty Dictionary. A hook failing in phase 2 returns its error after
	 * the world may already have changed, so the caller should end the
	 * session. The step limit belongs to US4, so max_episode_steps is not
	 * applied here. Emits episode_ended once every agent has finished.
	 */
	schola::Status step(const std::map<schola::AgentId, schola::Point> &p_actions,
			std::map<schola::AgentId, schola::AgentState> &r_states) override;

	// Non-owning pointers to each agent's GodotAgentAdapter, in scene-tree order.
	schola::Status get_agents(std::vector<schola::Agent *> &r_agents) const override;

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
};
