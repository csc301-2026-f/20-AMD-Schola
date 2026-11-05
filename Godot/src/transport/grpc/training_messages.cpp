// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "transport/grpc/training_messages.h"

#include "transport/grpc/space_conversion.h"

#include <string>
#include <utility>

namespace schola {
namespace {

void initial_state_to_proto(const InitialState &p_state, ::Schola::InitialState &r_message) {
	for (const auto &environment : p_state.environments) {
		auto &message = (*r_message.mutable_environment_states())[environment.first];
		for (const auto &agent : environment.second.agents) {
			auto &state = (*message.mutable_agent_states())[agent.first];
			// These reply contracts carry points without their definitions. US2
			// uses a flat Box shape and the wire's default dtype in that case.
			point_to_proto(agent.second.observation, Space(), *state.mutable_observations());
			state.mutable_info()->insert(agent.second.info.begin(), agent.second.info.end());
		}
	}
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

void to_proto(const InitialState &p_initial_state, ::Schola::State &r_message) {
	r_message.Clear();
	initial_state_to_proto(p_initial_state, *r_message.mutable_initial_state());
}

void to_proto(const StepResult &p_result, ::Schola::State &r_message) {
	r_message.Clear();
	auto *training = r_message.mutable_training_state();
	for (const auto &environment : p_result.state.environments) {
		auto *message = training->add_environment_states();
		for (const auto &agent : environment.agents) {
			agent_state_to_proto(agent.second, Space(), (*message->mutable_agent_states())[agent.first]);
		}
	}
	if (!p_result.initial_state.environments.empty()) {
		initial_state_to_proto(p_result.initial_state, *r_message.mutable_initial_state());
	}
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
