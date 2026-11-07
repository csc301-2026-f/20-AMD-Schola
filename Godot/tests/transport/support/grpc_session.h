// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

// The two actors in every GrpcConnector test, talking over a real localhost
// connection:
//
//   Python  A gRPC client that makes the same calls, in the same order, as
//           Schola's real Python client. It runs on its own thread.
//   Godot   A real ConnectorLoop and GrpcConnector driving a fake game
//           (FakeTrainingBackend), which records what it receives and replies
//           with whatever the test set up. It runs on the test's main thread.
//
// A normal session goes: Python says hello (start), asks what it can train
// (definition), sends resets and steps, then says goodbye (close).

#include "transport/grpc/grpc_connector.h"

#include "../../unit/support/fake_training_backend.h"

#include "GymConnector.grpc.pb.h"

#include <chrono>
#include <future>
#include <memory>
#include <string>

namespace schola::testing {

// How long either side waits before giving up. Long enough for a slow
// machine, short enough that a hang fails the test quickly.
inline constexpr std::chrono::milliseconds WAIT{ 5000 };

// Finds an unused port, so tests never collide with each other or with a real
// training session on port 8000.
inline int32_t free_port() {
	int port = 0;
	// gRPC will not start a server that has no services.
	::Schola::GymService::Service unused;
	grpc::ServerBuilder builder;
	builder.AddListeningPort("127.0.0.1:0", grpc::InsecureServerCredentials(), &port);
	builder.RegisterService(&unused);
	builder.BuildAndStart()->Shutdown();
	return port;
}

// Stands in for Schola's Python client. Each method is one call Python can make.
class Python {
public:
	explicit Python(int32_t p_port) {
		// Python accepts messages up to 100 MB; gRPC's default is 4 MB.
		grpc::ChannelArguments arguments;
		arguments.SetMaxReceiveMessageSize(100 * 1024 * 1024);
		stub = ::Schola::GymService::NewStub(grpc::CreateCustomChannel(
				"127.0.0.1:" + std::to_string(p_port), grpc::InsecureChannelCredentials(), arguments));
	}

	// "Hello, let's train." Also says how finished environments should reset.
	grpc::Status start(::Schola::AutoResetType p_mode = ::Schola::SAME_STEP) {
		grpc::ClientContext context;
		context.set_deadline(std::chrono::system_clock::now() + WAIT);
		// Like Python, wait for Godot to start listening instead of failing.
		context.set_wait_for_ready(true);
		::Schola::GymConnectorStartRequest request;
		request.set_autoreset_type(p_mode);
		::Schola::GymConnectorStartResponse response;
		return stub->StartGymConnector(&context, request, &response);
	}

	// "What can I train?" Godot answers with its environments, agents and spaces.
	grpc::Status request_definition(::Schola::TrainingDefinition &r_definition) {
		grpc::ClientContext context;
		context.set_deadline(std::chrono::system_clock::now() + WAIT);
		return stub->RequestTrainingDefinition(&context, ::Schola::TrainingDefinitionRequest(), &r_definition);
	}

	// A reset or a step. Godot answers with observations, rewards and so on.
	grpc::Status update(const ::Schola::StateUpdate &p_update, ::Schola::State &r_state,
			std::chrono::milliseconds p_deadline = WAIT) {
		grpc::ClientContext context;
		context.set_deadline(std::chrono::system_clock::now() + p_deadline);
		return stub->UpdateState(&context, p_update, &r_state);
	}

	// How Python says "I'm done" (CLOSED) or "something broke on my side" (ERROR).
	grpc::Status send_status(::Schola::CommunicatorStatus p_status) {
		::Schola::StateUpdate message;
		message.set_status(p_status);
		::Schola::State ignored;
		return update(message, ignored);
	}

	// The two calls every session starts with: start, then definition.
	bool connect() {
		::Schola::TrainingDefinition ignored;
		return start().ok() && request_definition(ignored).ok();
	}

private:
	std::unique_ptr<::Schola::GymService::Stub> stub;
};

// Runs p_script with its own Python client on a background thread, the way the
// real trainer runs in its own process. Get the script's result from the
// returned future.
template <typename Script>
auto run_python(int32_t p_port, Script p_script) {
	return std::async(std::launch::async, [p_port, p_script] {
		Python client(p_port);
		return p_script(client);
	});
}

// Stands in for a Godot game that is ready to be trained.
struct Godot {
	int32_t port = free_port();
	GrpcConnector connector{ GrpcConnectorSettings{ "127.0.0.1", port } }; // Listens for Python. The code under test.
	FakeTrainingBackend game; // Scripted replies; records every request.
	ConnectorLoop loop; // Passes each Python call to the game, one at a time.

	// Waits for Python's hello and publishes the game's definition.
	Status start(std::chrono::milliseconds p_timeout = WAIT) {
		return loop.start(connector, game, p_timeout);
	}

	// Handles one call from Python. In a real game this runs once per physics frame.
	Status tick(std::chrono::milliseconds p_timeout = WAIT) {
		return loop.tick(p_timeout);
	}
};

// Python's message for "take a step", with no actions, for one environment.
inline ::Schola::StateUpdate empty_step() {
	::Schola::StateUpdate message;
	message.mutable_step()->add_environments();
	return message;
}

// Puts one agent's chosen action into Python's step message.
inline void set_action(::Schola::EnvironmentStep &r_environment, const std::string &p_agent, int32_t p_action) {
	(*r_environment.mutable_updates())[p_agent].mutable_discrete_point()->set_value(p_action);
}

// What one agent reports after a step: what it sees now, and its reward.
inline AgentState agent_state(float p_observation, float p_reward) {
	AgentState state;
	state.observation = Point(BoxPoint{ { p_observation } });
	state.reward = p_reward;
	return state;
}

// Reads the single number an agent sees, as Python received it.
inline float observation(const ::Schola::Point &p_point) {
	return p_point.box_point().values(0);
}

} // namespace schola::testing
