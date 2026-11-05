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

	/** Captures fixed definitions from get_possible_agents(), including future spawn templates. */
	schola::Status initialize(std::map<schola::AgentId, schola::InteractionDefinition> &r_agents) override;

	/** Runs _reset_episode, rediscovers live descendants, and returns their initial observations.
	 * Freed/replaced nodes from previous episodes are not retained.
	 */
	schola::Status reset(const schola::ResetSettings &p_settings,
			std::map<schola::AgentId, schola::InitialAgentState> &r_states) override;

	/** Applies actions to the prior active roster, then discovers births and departures.
	 * Departures receive a terminal transition using their last observation and zero reward.
	 * Births receive an initial observation and zero reward, and act on the next call.
	 * Definitions must match the initialized possible roster. Finished IDs retire until reset.
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
	// A live agent found during the latest scene-tree scan.
	struct AgentEntry {
		schola::AgentId id;

		// Godot owns agent nodes and can free one at any time, so each call
		// looks the node up by ID instead of keeping a pointer that could
		// dangle. Departures are detected while refreshing the active roster.
		godot::ObjectID node_id;
	};

	ScholaEnvironment *node = nullptr; // Not owned.
	std::map<schola::AgentId, schola::InteractionDefinition> definitions;
	std::map<schola::AgentId, schola::AgentState> last_states;
	schola::Status collect_current_agents(std::vector<AgentEntry> &r_agents) const;
	bool initialized = false;
	bool episode_active = false;
	int64_t episode_step = 0;
};
