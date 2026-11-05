// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#if __has_include("GymConnector.pb.h")

#include "transport/grpc/training_messages.h"

#include "transport/grpc/space_conversion.h"

#include <catch_amalgamated.hpp>

using namespace schola;

TEST_CASE("training start decodes known modes and rejects unknown values", "[training][transport]") {
	const std::pair<::Schola::AutoResetType, AutoResetMode> modes[] = {
		{ ::Schola::SAME_STEP, AutoResetMode::SAME_STEP },
		{ ::Schola::NEXT_STEP, AutoResetMode::NEXT_STEP },
		{ ::Schola::DISABLED, AutoResetMode::DISABLED },
	};
	StartRequest request;
	::Schola::GymConnectorStartRequest message;
	REQUIRE(from_proto(message, request).is_ok());
	CHECK(request.autoreset_mode == AutoResetMode::SAME_STEP);
	for (const auto &mode : modes) {
		message.set_autoreset_type(mode.first);
		REQUIRE(from_proto(message, request).is_ok());
		CHECK(request.autoreset_mode == mode.second);
	}
	message.set_autoreset_type(static_cast<::Schola::AutoResetType>(99));
	const Status status = from_proto(message, request);
	CHECK(status.get_code() == StatusCode::INVALID_ARGUMENT);
	CHECK(status.get_message().find("99") != std::string::npos);
	CHECK(request.autoreset_mode == AutoResetMode::DISABLED);
}

TEST_CASE("training definitions preserve environment order and agent spaces", "[training][transport]") {
	TrainingDefinition definition;
	definition.environments.resize(3);
	InteractionDefinition agent;
	DictSpace observations;
	observations.entries.emplace_back("position", Space(BoxSpace{ { -1.0f }, { 1.0f }, { 1 } }));
	observations.entries.emplace_back("buttons", Space(MultiBinarySpace{ 2 }));
	agent.observation_space = Space(std::move(observations));
	agent.action_space = Space(MultiDiscreteSpace{ { 3, 5 } });
	agent.agent_type = "runner";
	definition.environments[0].agents["a"] = agent;
	definition.environments[0].agents["b"] = agent;
	definition.environments[2].agents["last"] = agent;
	::Schola::TrainingDefinition message;
	message.add_environment_definitions();
	to_proto(definition, message);
	REQUIRE(message.environment_definitions_size() == 3);
	for (int i = 0; i < 3; ++i) {
		const auto &agents = message.environment_definitions(i).agent_definitions();
		REQUIRE(agents.size() == definition.environments[i].agents.size());
		for (const auto &entry : definition.environments[i].agents) {
			REQUIRE(agents.contains(entry.first));
			InteractionDefinition decoded;
			REQUIRE(proto_to_interaction_definition(agents.at(entry.first), decoded).is_ok());
			CHECK(decoded.observation_space == entry.second.observation_space);
			CHECK(decoded.action_space == entry.second.action_space);
			CHECK(decoded.agent_type == entry.second.agent_type);
		}
	}
}

TEST_CASE("training updates decode actions and reset settings", "[training][transport]") {
	::Schola::StateUpdate message;
	ConnectorUpdate update;
	SECTION("step passes values through without space validation") {
		auto *environment = message.mutable_step()->add_environments();
		auto &point = (*environment->mutable_updates())["runner"];
		(*point.mutable_dict_point()->mutable_values())["z"].mutable_discrete_point()->set_value(-99);
		(*point.mutable_dict_point()->mutable_values())["a"].mutable_box_point()->add_values(10000.0f);
		message.mutable_step()->add_environments();
		REQUIRE(from_proto(message, update).is_ok());
		CHECK(update.kind == UpdateKind::STEP);
		REQUIRE(update.step.actions.size() == 2);
		CHECK(update.step.actions[1].empty());
		const auto *dict = update.step.actions[0].at("runner").get_if<DictPoint>();
		REQUIRE(dict != nullptr);
		REQUIRE(dict->entries.size() == 2);
		CHECK(dict->entries[0].first == "a");
		CHECK(*dict->find("z") == Point(DiscretePoint{ -99 }));
		CHECK(*dict->find("a") == Point(BoxPoint{ { 10000.0f } }));
	}
	SECTION("reset preserves absent and zero seeds and options") {
		auto &environments = *message.mutable_reset()->mutable_environments();
		environments[2].set_seed(0);
		(*environments[2].mutable_options())["track"] = "hard";
		environments[5];
		REQUIRE(from_proto(message, update).is_ok());
		CHECK(update.kind == UpdateKind::RESET);
		REQUIRE(update.reset.environments.size() == 2);
		CHECK(update.reset.environments.at(2).seed == 0);
		CHECK(update.reset.environments.at(2).options.at("track") == "hard");
		CHECK_FALSE(update.reset.environments.at(5).seed.has_value());
	}
	SECTION("closed takes priority over payload") {
		message.set_status(::Schola::CLOSED);
		message.mutable_step()->add_environments();
		REQUIRE(from_proto(message, update).is_ok());
		CHECK(update.kind == UpdateKind::CLOSE);
		CHECK(update.step.actions.empty());
	}
	SECTION("Python error becomes CLOSED") {
		message.set_status(::Schola::ERROR);
		const Status status = from_proto(message, update);
		CHECK(status.get_code() == StatusCode::CLOSED);
		CHECK(status.get_message().find("Python") != std::string::npos);
		CHECK(status.get_message().find("ERROR") != std::string::npos);
	}
	SECTION("missing payload") {
		CHECK(from_proto(message, update).get_code() == StatusCode::INVALID_ARGUMENT);
	}
	SECTION("malformed action leaves output intact") {
		update.kind = UpdateKind::CLOSE;
		(*message.mutable_step()->add_environments()->mutable_updates())["bad"];
		CHECK(from_proto(message, update).get_code() == StatusCode::INVALID_ARGUMENT);
		CHECK(update.kind == UpdateKind::CLOSE);
	}
}

TEST_CASE("training replies set independent state oneofs and replace reused messages", "[training][transport]") {
	InitialState initial;
	initial.environments[3].agents["runner"] = InitialAgentState{ Point(DiscretePoint{ 2 }), { { "spawn", "north" } } };
	initial.environments[5];
	::Schola::State message;
	message.mutable_training_state();
	to_proto(initial, message);
	CHECK_FALSE(message.has_training_state());
	REQUIRE(message.has_initial_state());
	REQUIRE(message.initial_state().environment_states().size() == 2);
	const auto &agent = message.initial_state().environment_states().at(3).agent_states().at("runner");
	CHECK(agent.observations().discrete_point().value() == 2);
	CHECK(agent.info().at("spawn") == "north");

	StepResult result;
	result.state.environments.resize(2);
	AgentState state;
	state.observation = Point(BoxPoint{ { 0.25f, -1.0f } });
	state.reward = 1.5f;
	state.terminated = true;
	state.truncated = true;
	state.info["lap"] = "2";
	result.state.environments[1].agents["runner"] = state;
	to_proto(result, message);
	REQUIRE(message.has_training_state());
	CHECK_FALSE(message.has_initial_state());
	REQUIRE(message.training_state().environment_states_size() == 2);
	CHECK(message.training_state().environment_states(0).agent_states().empty());
	AgentState decoded;
	REQUIRE(proto_to_agent_state(message.training_state().environment_states(1).agent_states().at("runner"), Space(BoxSpace{ { -1.0f, -1.0f }, { 1.0f, 1.0f }, { 2 } }), decoded).is_ok());
	CHECK(decoded.observation == state.observation);
	CHECK(decoded.reward == state.reward);
	CHECK(decoded.terminated);
	CHECK(decoded.truncated);
	CHECK(decoded.info == state.info);
	result.initial_state = initial;
	to_proto(result, message);
	CHECK(message.has_training_state());
	CHECK(message.has_initial_state());
	CHECK(message.initial_state().environment_states().at(3).agent_states().at("runner").info().at("spawn") == "north");
	to_proto(InitialState(), message);
	CHECK_FALSE(message.has_training_state());
	CHECK(message.has_initial_state());
	CHECK(message.initial_state().environment_states().empty());
}

TEST_CASE("training errors map to gRPC codes with RPC context", "[training][transport]") {
	CHECK(to_grpc_status(Status::ok(), "UpdateState").ok());
	CHECK(to_grpc_status(Status::ok(), "UpdateState").error_message().empty());
	const std::pair<StatusCode, grpc::StatusCode> codes[] = {
		{ StatusCode::INVALID_ARGUMENT, grpc::StatusCode::INVALID_ARGUMENT },
		{ StatusCode::INVALID_DATA, grpc::StatusCode::INVALID_ARGUMENT },
		{ StatusCode::NOT_FOUND, grpc::StatusCode::NOT_FOUND },
		{ StatusCode::FAILED_PRECONDITION, grpc::StatusCode::FAILED_PRECONDITION },
		{ StatusCode::INCOMPATIBLE, grpc::StatusCode::FAILED_PRECONDITION },
		{ StatusCode::TIMEOUT, grpc::StatusCode::DEADLINE_EXCEEDED },
		{ StatusCode::CLOSED, grpc::StatusCode::UNAVAILABLE },
		{ StatusCode::RUNTIME_FAILURE, grpc::StatusCode::INTERNAL },
	};
	for (const auto &entry : codes) {
		const auto status = to_grpc_status(Status::error(entry.first, "reason"), "UpdateState");
		CHECK(status.error_code() == entry.second);
		CHECK(status.error_message() == "UpdateState: reason");
	}
}

#endif
