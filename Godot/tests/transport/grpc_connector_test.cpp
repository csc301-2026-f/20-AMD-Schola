// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

// Tests for GrpcConnector, the gRPC server that Schola's Python trainer
// connects to. Each test is a short scene between a stand-in Python client and
// a stand-in Godot game; support/grpc_session.h explains the setup.

#if __has_include("GymConnector.grpc.pb.h")

#include "support/grpc_session.h"

#include <catch_amalgamated.hpp>

#include <thread>
#include <vector>

using namespace schola;
using namespace schola::testing;
using namespace std::chrono_literals;

namespace {

// Two environments with two agents each. Every agent gets a different reply,
// so a mix-up between agents or environments shows up as a wrong value.
void set_up_two_environments(FakeTrainingBackend &r_game) {
	InteractionDefinition agent;
	agent.observation_space = Space(BoxSpace{ { -1.0f }, { 1.0f }, { 1 } });
	agent.action_space = Space(DiscreteSpace{ 3 });
	r_game.definition.environments.resize(2);
	r_game.definition.environments[0].agents["a"] = agent;
	r_game.definition.environments[0].agents["b"] = agent;
	r_game.definition.environments[1].agents["c"] = agent;
	r_game.definition.environments[1].agents["d"] = agent;

	r_game.initial_state.environments[0].agents["a"].observation = Point(BoxPoint{ { 0.1f } });

	r_game.step_result.state.environments.resize(2);
	r_game.step_result.state.environments[0].agents["a"] = agent_state(0.2f, 1.0f);
	r_game.step_result.state.environments[0].agents["b"] = agent_state(0.3f, 2.0f);
	r_game.step_result.state.environments[1].agents["c"] = agent_state(0.4f, 3.0f);
	r_game.step_result.state.environments[1].agents["d"] = agent_state(0.5f, 4.0f);
	// Environment 1 finished and auto-reset during the step, so the reply also
	// carries where it restarted.
	r_game.step_result.initial_state.environments[1].agents["c"].observation = Point(BoxPoint{ { -0.5f } });
}

// Python's step with a different action for each of the four agents.
::Schola::StateUpdate four_different_actions() {
	::Schola::StateUpdate message;
	::Schola::EnvironmentStep *first = message.mutable_step()->add_environments();
	::Schola::EnvironmentStep *second = message.mutable_step()->add_environments();
	set_action(*first, "a", 0);
	set_action(*first, "b", 1);
	set_action(*second, "c", 2);
	set_action(*second, "d", 0);
	return message;
}

} // namespace

// The happy path, end to end: everything Python sends reaches the right agent,
// and everything the game sends back reaches Python under the right agent.
TEST_CASE("a full session: start, definition, reset, step, close", "[grpc]") {
	Godot godot;
	set_up_two_environments(godot.game);

	// Catch2 assertions are not thread-safe, so Python only records what it
	// received and the main thread checks it afterwards.
	::Schola::TrainingDefinition definition;
	::Schola::State after_reset;
	::Schola::State after_step;
	auto python = run_python(godot.port, [&](Python &client) {
		::Schola::StateUpdate reset;
		(*reset.mutable_reset()->mutable_environments())[0].set_seed(7);
		return client.start(::Schola::NEXT_STEP).ok() && client.request_definition(definition).ok() &&
				client.update(reset, after_reset).ok() && client.update(four_different_actions(), after_step).ok() &&
				client.send_status(::Schola::CLOSED).ok();
	});

	// Godot handles: hello and definition, then the reset, then the step, then goodbye.
	REQUIRE(godot.start().is_ok());
	REQUIRE(godot.tick().is_ok());
	REQUIRE(godot.tick().is_ok());
	CHECK(godot.tick().get_code() == StatusCode::CLOSED);
	REQUIRE(python.get());

	// The game received exactly what Python sent.
	CHECK(godot.game.mode == AutoResetMode::NEXT_STEP);
	CHECK(godot.game.resets.at(0).environments.at(0).seed == 7);
	const auto &actions = godot.game.steps.at(0).actions;
	CHECK(actions.at(0).at("a") == Point(DiscretePoint{ 0 }));
	CHECK(actions.at(0).at("b") == Point(DiscretePoint{ 1 }));
	CHECK(actions.at(1).at("c") == Point(DiscretePoint{ 2 }));
	CHECK(actions.at(1).at("d") == Point(DiscretePoint{ 0 }));

	// Python received exactly what the game sent, under the right environment and agent.
	CHECK(definition.environment_definitions(1).agent_definitions().contains("d"));
	CHECK(observation(after_reset.initial_state().environment_states().at(0).agent_states().at("a").observations()) == 0.1f);
	const auto &after_step_agents = after_step.training_state().environment_states();
	CHECK(after_step_agents.at(0).agent_states().at("b").reward() == 2.0f);
	CHECK(after_step_agents.at(1).agent_states().at("d").reward() == 4.0f);
	CHECK(observation(after_step_agents.at(1).agent_states().at("c").observations()) == 0.4f);
	CHECK(observation(after_step.initial_state().environment_states().at(1).agent_states().at("c").observations()) == -0.5f);

	// Saying goodbye shut the game down once.
	CHECK(godot.game.close_count == 1);
}

// Camera observations are big. gRPC rejects messages over 4 MB by default, so
// this checks that the connector raised its limit and an 8 MB image gets through.
TEST_CASE("an observation over gRPC's 4 MB default still reaches Python", "[grpc]") {
	Godot godot;
	// Two million floats is about 8 MB, the size of a large camera image.
	const std::vector<float> pixels(2'000'000, 0.5f);
	InteractionDefinition camera;
	camera.observation_space = Space(BoxSpace{ std::vector<float>(pixels.size(), 0.0f),
			std::vector<float>(pixels.size(), 1.0f), { static_cast<int32_t>(pixels.size()) } });
	camera.action_space = Space(DiscreteSpace{ 2 });
	godot.game.definition.environments.resize(1);
	godot.game.definition.environments[0].agents["camera"] = camera;
	godot.game.initial_state.environments[0].agents["camera"].observation = Point(BoxPoint{ pixels });

	::Schola::State after_reset;
	auto python = run_python(godot.port, [&](Python &client) {
		::Schola::StateUpdate reset;
		reset.mutable_reset();
		return client.connect() && client.update(reset, after_reset).ok();
	});

	REQUIRE(godot.start().is_ok());
	REQUIRE(godot.tick().is_ok());
	REQUIRE(python.get());
	const auto &camera_view = after_reset.initial_state().environment_states().at(0).agent_states().at("camera");
	CHECK(camera_view.observations().box_point().values_size() == static_cast<int>(pixels.size()));
}

// If nobody ever connects, the game must not wait forever. It should give up,
// and leave the port free so the next training session can use it.
TEST_CASE("Godot gives up when Python never connects, and frees the port", "[grpc]") {
	Godot godot;

	CHECK(godot.start(200ms).get_code() == StatusCode::TIMEOUT);
	CHECK(godot.game.close_count == 1);

	GrpcConnector next(GrpcConnectorSettings{ "127.0.0.1", godot.port });
	CHECK(next.open().is_ok());
}

// Python connects, then goes silent (for example, the trainer froze). The game
// should time out and shut the session down instead of freezing too.
TEST_CASE("Godot gives up when Python goes quiet mid-session", "[grpc]") {
	Godot godot;
	auto python = run_python(godot.port, [](Python &client) {
		return client.connect();
	});

	REQUIRE(godot.start().is_ok());
	REQUIRE(python.get());
	CHECK(godot.tick(200ms).get_code() == StatusCode::TIMEOUT);
	CHECK_FALSE(godot.loop.is_running());
	CHECK(godot.game.close_count == 1);
}

// The game breaks while running a step. Python should get a clear error that
// names the call and the reason, and the session should end so later calls fail.
TEST_CASE("a game failure reaches Python as an error", "[grpc]") {
	Godot godot;
	godot.game.definition.environments.resize(1);
	godot.game.step_status = Status::error(StatusCode::RUNTIME_FAILURE, "the physics engine crashed");

	grpc::Status step_status;
	grpc::Status later_status;
	auto python = run_python(godot.port, [&](Python &client) {
		::Schola::State ignored;
		bool connected = client.connect();
		step_status = client.update(empty_step(), ignored);
		later_status = client.update(empty_step(), ignored);
		return connected;
	});

	REQUIRE(godot.start().is_ok());
	CHECK(godot.tick().get_code() == StatusCode::RUNTIME_FAILURE);
	REQUIRE(python.get());

	CHECK(step_status.error_code() == grpc::StatusCode::INTERNAL);
	CHECK(step_status.error_message() == "UpdateState: the physics engine crashed");
	CHECK_FALSE(later_status.ok());
}

// Python hit a problem on its side and says so. The game should end the session
// cleanly rather than treat it as its own failure.
TEST_CASE("Python reporting an error ends the session cleanly", "[grpc]") {
	Godot godot;
	auto python = run_python(godot.port, [](Python &client) {
		return client.connect() && client.send_status(::Schola::ERROR).ok();
	});

	REQUIRE(godot.start().is_ok());
	CHECK(godot.tick().get_code() == StatusCode::CLOSED);
	CHECK(python.get());
	CHECK(godot.game.close_count == 1);
}

// Python sends a step but gives up before the game gets to it (for example, the
// trainer was killed). The game must notice, end the session, and never run that
// abandoned step.
TEST_CASE("Python hanging up mid-call ends the session without a hang", "[grpc]") {
	Godot godot;
	grpc::Status step_status;
	auto python = run_python(godot.port, [&](Python &client) {
		::Schola::State ignored;
		bool connected = client.connect();
		// Python gives up after 200 ms, before Godot gets to this call.
		step_status = client.update(empty_step(), ignored, 200ms);
		return connected;
	});

	REQUIRE(godot.start().is_ok());
	// Godot is busy elsewhere long enough for Python to give up.
	std::this_thread::sleep_for(600ms);
	CHECK(godot.tick().get_code() == StatusCode::CLOSED);
	REQUIRE(python.get());
	CHECK(step_status.error_code() == grpc::StatusCode::DEADLINE_EXCEEDED);
	CHECK(godot.game.steps.empty());
}

// Two games can't share a port. The second one should fail with an error that
// names the address, instead of silently stealing the first one's training.
// Shutting down must also be safe after that failure, and safe to repeat.
TEST_CASE("a taken port gives a clear error, and close is always safe", "[grpc]") {
	const int32_t port = free_port();
	GrpcConnector first(GrpcConnectorSettings{ "127.0.0.1", port });
	REQUIRE(first.open().is_ok());

	GrpcConnector second(GrpcConnectorSettings{ "127.0.0.1", port });
	const Status status = second.open();
	CHECK(status.get_code() == StatusCode::RUNTIME_FAILURE);
	CHECK(status.get_message().find("127.0.0.1:" + std::to_string(port)) != std::string::npos);

	second.close();
	second.close();
	first.close();
	first.close();
}

#endif
