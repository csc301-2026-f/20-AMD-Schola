// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/connector/connector.h"
#include "core/lifecycle/training_backend.h"

#include <godot_cpp/classes/node.hpp>

#include <cstdint>
#include <memory>

/**
 * Connects the current scene to Schola's Python trainer over gRPC.
 *
 * Add one to the scene you train, as you would place Unreal Schola's
 * AGymConnectorManager in a level. It trains every ScholaEnvironment in the
 * current scene, wherever it sits, and creates its own ScholaTrainingHost as an
 * internal child, so the scene needs nothing else.
 *
 * On the first physics frame, once every node in the scene is ready, it listens
 * on 127.0.0.1:port and waits for Python to connect. After that, each physics
 * frame blocks until Python's next reset or step and runs it, so an action and
 * its reward always land on the same frame. The game does not respond while it
 * waits; that is expected while training.
 *
 * When Python closes a session normally, the node keeps the port and waits for
 * Python's next session, as Unreal Schola does: Schola's RLlib trainer connects
 * once to read the agents and again to train. Each session gets a fresh
 * ScholaTrainingHost. Training ends when a session fails, or when Python does
 * not start another session within start_timeout_sec of closing one.
 *
 * It does nothing in the editor. The class belongs to the training add-on,
 * which exported games normally exclude, so keep it in a training-only scene
 * rather than in a scene you ship. Main thread only.
 */
class ScholaTrainingConnector : public godot::Node {
	GDCLASS(ScholaTrainingConnector, godot::Node)

public:
	ScholaTrainingConnector();

	// Stops a running session, so its gRPC threads never outlive the node.
	~ScholaTrainingConnector() override;

	// The port to listen on, 1 to 65535. -ScholaPort=<n> on the command line
	// overrides it, as in Unreal Schola.
	void set_port(int32_t p_port);
	int32_t get_port() const;

	// How long to wait for Python to connect; 0 waits indefinitely. The
	// default matches the Python client's environment_start_timeout.
	void set_start_timeout_sec(double p_seconds);
	double get_start_timeout_sec() const;

	// How long to wait for each of Python's updates; 0 waits indefinitely.
	void set_step_timeout_sec(double p_seconds);
	double get_step_timeout_sec() const;

	// True from Python's connection until the session ends.
	bool is_training() const;

	void _ready() override;
	void _physics_process(double p_delta) override;
	void _exit_tree() override;

protected:
	// Binds the properties, is_training(), and two signals. session_closed()
	// is emitted each time Python closes a session normally; the node then
	// waits for the next one. training_finished(error: String) is emitted
	// once, when training ends: with an empty string when Python finished
	// normally, and otherwise with the reason, which is also pushed as an
	// error.
	static void _bind_methods();

private:
	// Runs on the first physics frame, and again after each session Python
	// closes: replaces the host, opens the port, and waits for Python to start
	// a session.
	void start_session();
	// Creates the runtime's ScholaTrainingHost as an internal child, or returns
	// null if the runtime add-on is missing.
	godot::Node *create_host();
	// Ends training once and emits training_finished. p_normal means Python
	// finished on purpose, so p_status is not reported as an error.
	void finish(const schola::Status &p_status, bool p_normal);

	int32_t port = 8000;
	double start_timeout_sec = 45.0;
	double step_timeout_sec = 60.0;
	int32_t resolved_port = 0; // Chosen on the first session; 0 until then.
	int64_t completed_sessions = 0; // Sessions Python closed normally.
	bool finished = false; // training_finished has been emitted.

	// The session's parts: Python's side (gRPC), the game's side (the host,
	// reached through HostTrainingBackend), and the loop between them.
	godot::Node *host = nullptr; // Internal child; replaced each session.
	std::unique_ptr<schola::Connector> connector;
	std::unique_ptr<schola::TrainingBackend> backend;
	schola::ConnectorLoop loop;
};
