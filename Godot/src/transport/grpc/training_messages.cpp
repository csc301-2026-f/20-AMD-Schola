// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "transport/grpc/training_messages.h"

#include "transport/grpc/space_conversion.h"

#include <string>
#include <utility>

namespace schola {
namespace {

Status observation_space(const TrainingDefinition &p_definition, EnvironmentId p_environment, const AgentId &p_agent, const Space *&r_space) {
	if (p_environment < 0 || static_cast<size_t>(p_environment) >= p_definition.environments.size()) {
		return Status::error(StatusCode::INVALID_DATA, "State references undefined environment " + std::to_string(p_environment));
	}
	const auto &agents = p_definition.environments[p_environment].agents;
	const auto found = agents.find(p_agent);
	if (found == agents.end()) {
		return Status::error(StatusCode::INVALID_DATA, "State references undefined agent '" + p_agent + "' in environment " + std::to_string(p_environment));
	}
	r_space = &found->second.observation_space;
	return Status::ok();
}

Status initial_state_to_proto(const InitialState &p_state, const TrainingDefinition &p_definition, ::Schola::InitialState &r_message) {
	for (const auto &environment : p_state.environments) {
		if (environment.first < 0 || static_cast<size_t>(environment.first) >= p_definition.environments.size()) {
			return Status::error(StatusCode::INVALID_DATA, "Initial state references undefined environment " + std::to_string(environment.first));
		}
		auto &message = (*r_message.mutable_environment_states())[environment.first];
		for (const auto &agent : environment.second.agents) {
			const Space *space = nullptr;
			Status status = observation_space(p_definition, environment.first, agent.first, space);
			if (!status.is_ok()) {
				return status;
			}
			auto &state = (*message.mutable_agent_states())[agent.first];
			point_to_proto(agent.second.observation, *space, *state.mutable_observations());
			state.mutable_info()->insert(agent.second.info.begin(), agent.second.info.end());
		}
	}
	return Status::ok();
}

} // namespace

Status from_proto(const ::Schola::GymConnectorStartRequest &p_message, StartRequest &r_request) {
	switch (p_message.autoreset_type()) {
		case ::Schola::SAME_STEP:
			r_request.autoreset_mode = AutoResetMode::SAME_STEP;
			break;
		case ::Schola::NEXT_STEP:
			r_request.autoreset_mode = AutoResetMode::NEXT_STEP;
			break;
		case ::Schola::DISABLED:
			r_request.autoreset_mode = AutoResetMode::DISABLED;
			break;
		default:
			return Status::error(StatusCode::INVALID_ARGUMENT, "Unknown autoreset_type " + std::to_string(static_cast<int>(p_message.autoreset_type())));
	}
	return Status::ok();
}

void to_proto(const TrainingDefinition &p_definition, ::Schola::TrainingDefinition &r_message) {
	r_message.Clear();
	for (const auto &environment : p_definition.environments) {
		auto *message = r_message.add_environment_definitions();
		for (const auto &agent : environment.agents) {
			interaction_definition_to_proto(agent.second, (*message->mutable_agent_definitions())[agent.first]);
		}
	}
}

Status from_proto(const ::Schola::StateUpdate &p_message, ConnectorUpdate &r_update) {
	ConnectorUpdate update;
	if (p_message.status() == ::Schola::CLOSED) {
		update.kind = UpdateKind::CLOSE;
	} else if (p_message.status() == ::Schola::ERROR) {
		// StateUpdates.proto carries only the status, with no report text field.
		return Status::error(StatusCode::CLOSED, "Python reported ERROR in StateUpdate");
	} else {
		if (p_message.status() != ::Schola::GOOD) {
			return Status::error(StatusCode::INVALID_ARGUMENT, "Unknown StateUpdate status " + std::to_string(static_cast<int>(p_message.status())));
		}
		switch (p_message.update_case()) {
			case ::Schola::StateUpdate::kReset:
				update.kind = UpdateKind::RESET;
				for (const auto &environment : p_message.reset().environments()) {
					auto &settings = update.reset.environments[environment.first];
					if (environment.second.has_seed()) {
						settings.seed = environment.second.seed();
					}
					settings.options.insert(environment.second.options().begin(), environment.second.options().end());
				}
				break;
			case ::Schola::StateUpdate::kStep:
				update.kind = UpdateKind::STEP;
				for (const auto &environment : p_message.step().environments()) {
					auto &actions = update.step.actions.emplace_back();
					for (const auto &agent : environment.updates()) {
						Point point;
						Status status = proto_to_point(agent.second, point);
						if (!status.is_ok()) {
							return status;
						}
						actions.emplace(agent.first, std::move(point));
					}
				}
				break;
			default:
				return Status::error(StatusCode::INVALID_ARGUMENT, "StateUpdate has no reset or step");
		}
	}
	r_update = std::move(update);
	return Status::ok();
}

Status to_proto(const InitialState &p_initial_state, const TrainingDefinition &p_definition, ::Schola::State &r_message) {
	::Schola::State message;
	Status status = initial_state_to_proto(p_initial_state, p_definition, *message.mutable_initial_state());
	if (status.is_ok()) {
		r_message.Swap(&message);
	}
	return status;
}

Status to_proto(const StepResult &p_result, const TrainingDefinition &p_definition, ::Schola::State &r_message) {
	if (p_result.state.environments.size() > p_definition.environments.size()) {
		return Status::error(StatusCode::INVALID_DATA, "Training state has more environments than its definition");
	}
	::Schola::State reply;
	auto *training = reply.mutable_training_state();
	for (size_t i = 0; i < p_result.state.environments.size(); ++i) {
		auto *message = training->add_environment_states();
		for (const auto &agent : p_result.state.environments[i].agents) {
			const Space *space = nullptr;
			Status status = observation_space(p_definition, static_cast<EnvironmentId>(i), agent.first, space);
			if (!status.is_ok()) {
				return status;
			}
			agent_state_to_proto(agent.second, *space, (*message->mutable_agent_states())[agent.first]);
		}
	}
	if (!p_result.initial_state.environments.empty()) {
		Status status = initial_state_to_proto(p_result.initial_state, p_definition, *reply.mutable_initial_state());
		if (!status.is_ok()) {
			return status;
		}
	}
	r_message.Swap(&reply);
	return Status::ok();
}

grpc::Status to_grpc_status(const Status &p_status, std::string_view p_rpc) {
	grpc::StatusCode code;
	switch (p_status.get_code()) {
		case StatusCode::OK:
			return grpc::Status::OK;
		case StatusCode::INVALID_ARGUMENT:
		case StatusCode::INVALID_DATA:
			code = grpc::StatusCode::INVALID_ARGUMENT;
			break;
		case StatusCode::NOT_FOUND:
			code = grpc::StatusCode::NOT_FOUND;
			break;
		case StatusCode::FAILED_PRECONDITION:
		case StatusCode::INCOMPATIBLE:
			code = grpc::StatusCode::FAILED_PRECONDITION;
			break;
		case StatusCode::TIMEOUT:
			code = grpc::StatusCode::DEADLINE_EXCEEDED;
			break;
		case StatusCode::CLOSED:
			code = grpc::StatusCode::UNAVAILABLE;
			break;
		case StatusCode::RUNTIME_FAILURE:
			code = grpc::StatusCode::INTERNAL;
			break;
		default:
			code = grpc::StatusCode::INTERNAL;
			break;
	}
	return grpc::Status(code, std::string(p_rpc) + ": " + p_status.get_message());
}

} // namespace schola
