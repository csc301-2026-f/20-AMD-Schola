// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "transport/grpc/training_messages.h"

#include "transport/grpc/space_conversion.h"

#include <string>
#include <utility>

// Translates between the GymService protobuf messages Python sends and
// receives and the engine-independent types ConnectorLoop works with.
//
// Every function here is pure: no threads, no network, no Godot. Outputs are
// built in a local first and only moved into r_* on success, so a failed
// conversion never leaves a half-written message behind.

namespace schola {

namespace {

/** "environment 0, agent "runner"" — prefixed to errors so Python's traceback says where. */
std::string where(EnvironmentId p_environment, const AgentId &p_agent) {
	return "environment " + std::to_string(p_environment) + ", agent \"" + p_agent + "\"";
}

/**
 * Finds the agent's definition, which holds the spaces its points are read
 * and written with.
 *
 * Returns null if the environment or agent was never defined. That means
 * Python or the backend named something that is not part of this session.
 */
const InteractionDefinition *find_agent(const TrainingDefinition &p_definition, EnvironmentId p_environment, const AgentId &p_agent) {
	if (p_environment < 0 || static_cast<size_t>(p_environment) >= p_definition.environments.size()) {
		return nullptr;
	}
	const std::map<AgentId, InteractionDefinition> &agents = p_definition.environments[p_environment].agents;
	auto found = agents.find(p_agent);
	return found == agents.end() ? nullptr : &found->second;
}

Status unknown_agent(EnvironmentId p_environment, const AgentId &p_agent) {
	return Status::error(StatusCode::NOT_FOUND,
			where(p_environment, p_agent) + " is not in the training definition sent at startup.");
}

void reset_from_proto(const ::Schola::Reset &p_message, ResetRequest &r_request) {
	// Python only includes environments it has a seed or options for. A missing
	// environment still resets, with default settings.
	for (const auto &entry : p_message.environments()) {
		const ::Schola::EnvironmentSettings &settings_message = entry.second;
		ResetSettings &settings = r_request.environments[entry.first];
		if (settings_message.has_seed()) {
			settings.seed = settings_message.seed();
		}
		settings.options.insert(settings_message.options().begin(), settings_message.options().end());
	}
}

Status step_from_proto(const ::Schola::Step &p_message, const TrainingDefinition &p_definition, StepRequest &r_request) {
	// Python sends one entry per environment, in EnvironmentId order, so an
	// entry's position is its environment ID.
	for (EnvironmentId environment = 0; environment < p_message.environments_size(); ++environment) {
		std::map<AgentId, Point> &actions = r_request.actions.emplace_back();

		for (const auto &entry : p_message.environments(environment).updates()) {
			const AgentId &agent_id = entry.first;
			const InteractionDefinition *agent = find_agent(p_definition, environment, agent_id);
			if (agent == nullptr) {
				return unknown_agent(environment, agent_id);
			}

			// The action space gives the point its shape (Box) and key order (Dict).
			Status status = proto_to_point(entry.second, agent->action_space, actions[agent_id]);
			if (!status.is_ok()) {
				return Status::error(status.get_code(), where(environment, agent_id) + ", action: " + status.get_message());
			}
		}
	}
	return Status::ok();
}

Status initial_state_to_proto(const InitialState &p_state, const TrainingDefinition &p_definition, ::Schola::InitialState &r_message) {
	for (const auto &[environment, environment_state] : p_state.environments) {
		auto &agent_messages = *(*r_message.mutable_environment_states())[environment].mutable_agent_states();

		for (const auto &[agent_id, agent_state] : environment_state.agents) {
			const InteractionDefinition *agent = find_agent(p_definition, environment, agent_id);
			if (agent == nullptr) {
				return unknown_agent(environment, agent_id);
			}

			// US2 only converts full AgentStates, so a reset's InitialAgentState is
			// assembled here from the same point conversion.
			::Schola::InitialAgentState &message = agent_messages[agent_id];
			point_to_proto(agent_state.observation, agent->observation_space, *message.mutable_observations());
			for (const auto &[key, value] : agent_state.info) {
				(*message.mutable_info())[key] = value;
			}
		}
	}
	return Status::ok();
}

grpc::StatusCode to_grpc_code(StatusCode p_code) {
	switch (p_code) {
		case StatusCode::OK:
			return grpc::StatusCode::OK;
		case StatusCode::INVALID_ARGUMENT:
		case StatusCode::INVALID_DATA:
			return grpc::StatusCode::INVALID_ARGUMENT;
		case StatusCode::NOT_FOUND:
			return grpc::StatusCode::NOT_FOUND;
		case StatusCode::FAILED_PRECONDITION:
		case StatusCode::INCOMPATIBLE:
			return grpc::StatusCode::FAILED_PRECONDITION;
		case StatusCode::TIMEOUT:
			return grpc::StatusCode::DEADLINE_EXCEEDED;
		case StatusCode::CLOSED:
			return grpc::StatusCode::UNAVAILABLE;
		case StatusCode::RUNTIME_FAILURE:
			return grpc::StatusCode::INTERNAL;
	}
	return grpc::StatusCode::INTERNAL;
}

} // namespace

Status from_proto(const ::Schola::GymConnectorStartRequest &p_message, StartRequest &r_request) {
	switch (p_message.autoreset_type()) {
		case ::Schola::SAME_STEP:
			r_request.autoreset_mode = AutoResetMode::SAME_STEP;
			return Status::ok();
		case ::Schola::NEXT_STEP:
			r_request.autoreset_mode = AutoResetMode::NEXT_STEP;
			return Status::ok();
		case ::Schola::DISABLED:
			r_request.autoreset_mode = AutoResetMode::DISABLED;
			return Status::ok();
		default:
			// proto3 keeps enum values it does not recognize, so a newer Python
			// client can send a mode this build has never heard of.
			return Status::error(StatusCode::INVALID_ARGUMENT,
					"Python asked for auto-reset mode " + std::to_string(p_message.autoreset_type()) +
							", which this build does not support. Supported modes: SAME_STEP, NEXT_STEP, DISABLED.");
	}
}

void to_proto(const TrainingDefinition &p_definition, ::Schola::TrainingDefinition &r_message) {
	::Schola::TrainingDefinition message;
	for (const EnvironmentDefinition &environment : p_definition.environments) {
		auto &agent_messages = *message.add_environment_definitions()->mutable_agent_definitions();
		for (const auto &[agent_id, agent] : environment.agents) {
			interaction_definition_to_proto(agent, agent_messages[agent_id]);
		}
	}
	r_message = std::move(message);
}

Status from_proto(const ::Schola::StateUpdate &p_message, const TrainingDefinition &p_definition, ConnectorUpdate &r_update) {
	ConnectorUpdate update;

	// The status comes first because Python's close message carries no update.
	// ERROR is handled by `default` rather than named: Windows headers define
	// ERROR as a macro, which would break the build there.
	switch (p_message.status()) {
		case ::Schola::GOOD:
			break;
		case ::Schola::CLOSED:
			update.kind = UpdateKind::CLOSE;
			r_update = std::move(update);
			return Status::ok();
		default:
			return Status::error(StatusCode::CLOSED,
					"Python reported an error (CommunicatorStatus " + std::to_string(p_message.status()) +
							") and ended the training session.");
	}

	switch (p_message.update_case()) {
		case ::Schola::StateUpdate::kReset:
			update.kind = UpdateKind::RESET;
			reset_from_proto(p_message.reset(), update.reset);
			break;
		case ::Schola::StateUpdate::kStep: {
			update.kind = UpdateKind::STEP;
			Status status = step_from_proto(p_message.step(), p_definition, update.step);
			if (!status.is_ok()) {
				return status;
			}
			break;
		}
		case ::Schola::StateUpdate::UPDATE_NOT_SET:
			return Status::error(StatusCode::INVALID_ARGUMENT,
					"UpdateState carried neither a reset nor a step, and its status was not CLOSED.");
	}

	r_update = std::move(update);
	return Status::ok();
}

Status to_proto(const InitialState &p_initial_state, const TrainingDefinition &p_definition, ::Schola::State &r_message) {
	::Schola::State message;
	Status status = initial_state_to_proto(p_initial_state, p_definition, *message.mutable_initial_state());
	if (!status.is_ok()) {
		return status;
	}
	r_message = std::move(message);
	return Status::ok();
}

Status to_proto(const StepResult &p_result, const TrainingDefinition &p_definition, ::Schola::State &r_message) {
	::Schola::State message;

	// One EnvironmentState per environment, in EnvironmentId order, which is
	// how Python matches them back up.
	::Schola::TrainingState &training_state = *message.mutable_training_state();
	for (EnvironmentId environment = 0; environment < static_cast<EnvironmentId>(p_result.state.environments.size()); ++environment) {
		auto &agent_messages = *training_state.add_environment_states()->mutable_agent_states();

		for (const auto &[agent_id, agent_state] : p_result.state.environments[environment].agents) {
			const InteractionDefinition *agent = find_agent(p_definition, environment, agent_id);
			if (agent == nullptr) {
				return unknown_agent(environment, agent_id);
			}
			agent_state_to_proto(agent_state, agent->observation_space, agent_messages[agent_id]);
		}
	}

	// Python checks HasField("initial_state"), so it is only set when a
	// SAME_STEP auto-reset actually produced one.
	if (!p_result.initial_state.environments.empty()) {
		Status status = initial_state_to_proto(p_result.initial_state, p_definition, *message.mutable_initial_state());
		if (!status.is_ok()) {
			return status;
		}
	}

	r_message = std::move(message);
	return Status::ok();
}

grpc::Status to_grpc_status(const Status &p_status, std::string_view p_rpc) {
	if (p_status.is_ok()) {
		return grpc::Status::OK;
	}
	return grpc::Status(to_grpc_code(p_status.get_code()), std::string(p_rpc) + ": " + p_status.get_message());
}

} // namespace schola
