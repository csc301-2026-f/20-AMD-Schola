// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "core/lifecycle/environment_lifecycle.h"

#include <algorithm>
#include <utility>

namespace schola {

namespace {

template <typename Left, typename Right>
bool declared_agent_ids(const Left &p_left, const Right &p_right) {
	return std::all_of(p_left.begin(), p_left.end(), [&](const auto &entry) {
		return p_right.find(entry.first) != p_right.end();
	});
}

} // namespace

EnvironmentLifecycle::EnvironmentLifecycle(
		EnvironmentId p_id,
		Environment &p_environment) :
		id(p_id),
		environment(p_environment) {
}

EnvironmentId EnvironmentLifecycle::get_id() const {
	return id;
}

LifecycleState EnvironmentLifecycle::get_state() const {
	return state;
}

uint64_t EnvironmentLifecycle::get_episode_step_count() const {
	return episode_step_count;
}

uint64_t EnvironmentLifecycle::get_episode_count() const {
	return episode_num;
}

const EnvironmentDefinition &EnvironmentLifecycle::get_definition() const {
	return definition;
}

Status EnvironmentLifecycle::initialize() {
	if (state != LifecycleState::UNINITIALIZED) {
		return Status::error(StatusCode::FAILED_PRECONDITION,
				"environment lifecycle is already initialized");
	}

	std::map<AgentId, InteractionDefinition> agents;
	Status result = environment.initialize(agents);
	if (!result.is_ok()) {
		state = LifecycleState::FAULTED;
		return result;
	}
	if (agents.empty()) {
		state = LifecycleState::FAULTED;
		return Status::error(StatusCode::INVALID_DATA, "environment must declare at least one agent");
	}

	definition = EnvironmentDefinition{ agents };
	state = LifecycleState::RESET_PENDING;
	return Status::ok();
}

Status EnvironmentLifecycle::reset(const ResetSettings &p_settings, InitialEnvironmentState &r_initial_state) {
	if (state != LifecycleState::RESET_PENDING && state != LifecycleState::ACTIVE && state != LifecycleState::COMPLETE) {
		return Status::error(StatusCode::FAILED_PRECONDITION,
				"environment is not in a resettable state");
	}

	std::map<AgentId, InitialAgentState> agents;
	Status result = environment.reset(p_settings, agents);

	if (!result.is_ok()) {
		state = LifecycleState::FAULTED;
		return result;
	}
	if (!declared_agent_ids(agents, definition.agents)) {
		state = LifecycleState::FAULTED;
		return Status::error(StatusCode::INVALID_DATA, "reset returned an undeclared agent");
	}

	last_state.agents.clear();
	for (const auto &[agent_id, initial] : agents) {
		last_state.agents.emplace(agent_id, AgentState{ initial.observation, 0.0f, false, false, initial.info });
	}
	r_initial_state.agents = std::move(agents);
	episode_step_count = 0;
	episode_num++;
	state = LifecycleState::ACTIVE;
	return Status::ok();
}

Status EnvironmentLifecycle::step(const std::map<AgentId, Point> &p_actions, EnvironmentState &r_state) {
	if (state != LifecycleState::ACTIVE) {
		return Status::error(StatusCode::FAILED_PRECONDITION,
				"environment is not in an active state");
	}
	size_t unfinished_count = 0;
	for (const auto &[agent_id, previous] : last_state.agents) {
		if (previous.terminated || previous.truncated) {
			continue;
		}
		++unfinished_count;
		if (p_actions.find(agent_id) == p_actions.end()) {
			return Status::error(StatusCode::INVALID_ARGUMENT, "missing action for unfinished agent " + agent_id);
		}
	}
	if (p_actions.size() != unfinished_count) {
		return Status::error(StatusCode::INVALID_ARGUMENT, "actions must contain only currently active agents");
	}

	std::map<AgentId, AgentState> step_states;
	Status result = environment.step(p_actions, step_states);
	if (!result.is_ok()) {
		state = LifecycleState::FAULTED;
		return result;
	}
	bool valid = declared_agent_ids(step_states, definition.agents);
	for (const auto &[agent_id, action] : p_actions) {
		valid = valid && step_states.count(agent_id) != 0;
	}
	for (const auto &[agent_id, value] : step_states) {
		const auto previous = last_state.agents.find(agent_id);
		if (previous != last_state.agents.end() && (previous->second.terminated || previous->second.truncated)) {
			valid = false;
		}
	}
	if (!valid) {
		state = LifecycleState::FAULTED;
		return Status::error(StatusCode::INVALID_DATA, "step must return all acting agents and only new, declared births");
	}

	episode_step_count++;

	for (const auto &[agent_id, agent_state] : step_states) {
		last_state.agents[agent_id] = agent_state;
	}

	const bool all_agents_done = !last_state.agents.empty() && std::all_of(last_state.agents.begin(), last_state.agents.end(), [](const auto &p_entry) { return p_entry.second.terminated || p_entry.second.truncated; });

	state = all_agents_done ? LifecycleState::COMPLETE : LifecycleState::ACTIVE;
	r_state = last_state;
	return Status::ok();
}

Status EnvironmentLifecycle::close() {
	last_state.agents.clear();
	episode_step_count = 0;
	state = LifecycleState::CLOSED;
	return Status::ok();
}

} // namespace schola
