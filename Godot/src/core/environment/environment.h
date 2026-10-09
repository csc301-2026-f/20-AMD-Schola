// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/common/types.h"
#include "core/environment/interaction_definition.h"
#include "core/spaces/point.h"

#include <cstdint>
#include <map>
#include <optional>
#include <string>

namespace schola {

// Python's reset(seed=..., options=...).
struct ResetSettings {
	// Set when Python passes a seed. A seeded reset re-seeds the environment's random generator;
	// an unseeded reset continues the current stream, matching Gymnasium.
	std::optional<int32_t> seed;
	std::map<std::string, std::string> options;
};

struct InitialAgentState {
	Point observation; // First observation of the episode.
	std::map<std::string, std::string> info; // Free-form data for Python's info dict.
};

struct AgentState {
	Point observation; // Observation after the actions and one physics frame.
	float reward = 0.0f; // Reward for this step.
	bool terminated = false; // The episode ended for this agent, e.g. goal reached or failure.
	bool truncated = false; // The episode was cut short, e.g. a time limit.
	std::map<std::string, std::string> info; // Free-form data for Python's info dict.
};

// One trainable environment containing at least one agent (Unreal: IScholaEnvironment). It knows
// nothing about sockets, RPC, or protocol messages. Godot physics runs between apply_actions() and
// collect_states(), so a step cannot be a single call. Output parameters remain unchanged whenever
// an operation returns a non-OK Status.
class Environment {
public:
	virtual ~Environment() = default;

	// Declares every agent and its spaces. Called once before the first reset; agent membership
	// and definitions are fixed afterwards. Invalid or incomplete configuration, including an
	// environment with no agents, returns INVALID_ARGUMENT with a message listing every problem.
	virtual Status initialize(std::map<AgentId, InteractionDefinition> &r_agents) = 0;

	// Starts a new episode and reports the first observation of every agent.
	virtual Status reset(const ResetSettings &p_settings, std::map<AgentId, InitialAgentState> &r_states) = 0;

	// Applies one action per agent before a physics frame. p_actions contains only agents that are
	// still running, and every action has already been validated by the caller.
	virtual Status apply_actions(const std::map<AgentId, Point> &p_actions) = 0;

	// Called after one physics frame. Reports one owned AgentState for each agent that received an
	// action in the preceding apply_actions().
	virtual Status collect_states(std::map<AgentId, AgentState> &r_states) = 0;
};

} // namespace schola
