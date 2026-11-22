// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

// Test-only stand-in for Schola's Python client over real gRPC, so GdUnit4 can
// drive a ScholaTrainingConnector node end to end. It connects the way
// `schola rllib train` does: one session to read the agents, closed with
// CLOSED, then a second session on the same port that trains. Compiled into
// the training extension only with integration_tests=yes.
//
// The connector blocks Godot's main thread while it waits for Python, so the
// client runs on its own thread, as the real trainer runs in its own process.
// The test polls is_done() between physics frames.
#include "GymConnector.grpc.pb.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <grpcpp/grpcpp.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

class ScholaGrpcTestClient : public godot::RefCounted {
	GDCLASS(ScholaGrpcTestClient, godot::RefCounted)

public:
	~ScholaGrpcTestClient() override {
		if (worker.joinable()) {
			worker.join();
		}
	}

	// Starts the client thread. It runs a discovery session (start,
	// definition, CLOSED), then a training session (start, definition, reset,
	// CLOSED), each call waiting up to p_timeout_sec for Godot.
	void connect_twice(int32_t p_port, double p_timeout_sec) {
		if (worker.joinable()) {
			return;
		}
		const auto timeout = std::chrono::milliseconds(static_cast<int64_t>(p_timeout_sec * 1000.0));
		worker = std::thread([this, p_port, timeout] { run(p_port, timeout); });
	}

	// True once both sessions finished or one of them failed.
	bool is_done() const {
		return done.load();
	}

	// Empty if both sessions succeeded, otherwise what failed.
	godot::String get_error() const {
		std::lock_guard<std::mutex> lock(mutex);
		return godot::String::utf8(error.c_str());
	}

	// One entry per session that read the definition: the agent IDs of
	// environment 0, sorted.
	godot::Array get_session_agents() const {
		std::lock_guard<std::mutex> lock(mutex);
		godot::Array sessions;
		for (const std::vector<std::string> &agents : session_agents) {
			godot::PackedStringArray ids;
			for (const std::string &id : agents) {
				ids.push_back(godot::String::utf8(id.c_str()));
			}
			sessions.push_back(ids);
		}
		return sessions;
	}

	// How many agents the training session's reset returned for environment 0.
	int64_t get_reset_agent_count() const {
		return reset_agent_count.load();
	}

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("connect_twice", "port", "timeout_sec"), &ScholaGrpcTestClient::connect_twice);
		godot::ClassDB::bind_method(godot::D_METHOD("is_done"), &ScholaGrpcTestClient::is_done);
		godot::ClassDB::bind_method(godot::D_METHOD("get_error"), &ScholaGrpcTestClient::get_error);
		godot::ClassDB::bind_method(godot::D_METHOD("get_session_agents"), &ScholaGrpcTestClient::get_session_agents);
		godot::ClassDB::bind_method(godot::D_METHOD("get_reset_agent_count"), &ScholaGrpcTestClient::get_reset_agent_count);
	}

private:
	void run(int32_t p_port, std::chrono::milliseconds p_timeout) {
		std::string failure = session(p_port, p_timeout, false);
		if (failure.empty()) {
			failure = session(p_port, p_timeout, true);
		}
		{
			std::lock_guard<std::mutex> lock(mutex);
			error = failure;
		}
		done.store(true);
	}

	// One session on a new channel, as Python opens one per environment
	// object. Returns an empty string on success.
	std::string session(int32_t p_port, std::chrono::milliseconds p_timeout, bool p_reset) {
		std::unique_ptr<::Schola::GymService::Stub> stub = ::Schola::GymService::NewStub(grpc::CreateChannel(
				"127.0.0.1:" + std::to_string(p_port), grpc::InsecureChannelCredentials()));
		const char *name = p_reset ? "training session" : "discovery session";

		{
			grpc::ClientContext context;
			context.set_deadline(std::chrono::system_clock::now() + p_timeout);
			// Like Python, wait for Godot to listen instead of failing at once.
			context.set_wait_for_ready(true);
			::Schola::GymConnectorStartRequest request;
			request.set_autoreset_type(::Schola::DISABLED);
			::Schola::GymConnectorStartResponse response;
			const grpc::Status status = stub->StartGymConnector(&context, request, &response);
			if (!status.ok()) {
				return std::string(name) + " start: " + status.error_message();
			}
		}

		{
			grpc::ClientContext context;
			context.set_deadline(std::chrono::system_clock::now() + p_timeout);
			::Schola::TrainingDefinition definition;
			const grpc::Status status = stub->RequestTrainingDefinition(&context, ::Schola::TrainingDefinitionRequest(), &definition);
			if (!status.ok()) {
				return std::string(name) + " definition: " + status.error_message();
			}
			if (definition.environment_definitions_size() < 1) {
				return std::string(name) + " definition: no environments";
			}
			std::vector<std::string> agents;
			for (const auto &[id, agent] : definition.environment_definitions(0).agent_definitions()) {
				(void)agent;
				agents.push_back(id);
			}
			std::sort(agents.begin(), agents.end());
			std::lock_guard<std::mutex> lock(mutex);
			session_agents.push_back(std::move(agents));
		}

		if (p_reset) {
			grpc::ClientContext context;
			context.set_deadline(std::chrono::system_clock::now() + p_timeout);
			::Schola::StateUpdate update;
			update.mutable_reset();
			::Schola::State state;
			const grpc::Status status = stub->UpdateState(&context, update, &state);
			if (!status.ok()) {
				return std::string(name) + " reset: " + status.error_message();
			}
			const auto &environments = state.initial_state().environment_states();
			const auto environment = environments.find(0);
			reset_agent_count.store(environment == environments.end() ? 0 : environment->second.agent_states_size());
		}

		{
			grpc::ClientContext context;
			context.set_deadline(std::chrono::system_clock::now() + p_timeout);
			::Schola::StateUpdate update;
			update.set_status(::Schola::CLOSED);
			::Schola::State ignored;
			const grpc::Status status = stub->UpdateState(&context, update, &ignored);
			if (!status.ok()) {
				return std::string(name) + " close: " + status.error_message();
			}
		}
		return std::string();
	}

	std::thread worker;
	std::atomic<bool> done{ false };
	std::atomic<int64_t> reset_agent_count{ 0 };
	mutable std::mutex mutex; // Guards error and session_agents.
	std::string error;
	std::vector<std::vector<std::string>> session_agents;
};

void register_schola_grpc_test_client() {
	GDREGISTER_CLASS(ScholaGrpcTestClient);
}
