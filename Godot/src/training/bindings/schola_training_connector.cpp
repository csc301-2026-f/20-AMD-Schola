// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "training/bindings/schola_training_connector.h"

#include "training/bindings/host_training_backend.h"
#include "transport/grpc/grpc_connector.h"

#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <string>

namespace {

constexpr int32_t MIN_PORT = 1;
constexpr int32_t MAX_PORT = 65535;

std::chrono::milliseconds to_milliseconds(double p_seconds) {
	return std::chrono::milliseconds(static_cast<int64_t>(std::llround(p_seconds * 1000.0)));
}

godot::String to_godot_string(const std::string &p_text) {
	return godot::String::utf8(p_text.c_str());
}

// Unreal Schola reads -ScholaPort=<n>. Godot keeps arguments it does not
// recognize, and puts anything after "--" in the user arguments, so both lists
// are searched. One or two leading dashes are accepted.
schola::Status resolve_port(int32_t p_default, int32_t &r_port) {
	godot::OS *os = godot::OS::get_singleton();
	const godot::PackedStringArray lists[] = { os->get_cmdline_args(), os->get_cmdline_user_args() };
	for (const godot::PackedStringArray &arguments : lists) {
		for (int64_t index = 0; index < arguments.size(); ++index) {
			const godot::String argument = arguments[index];
			if (!argument.begins_with("-ScholaPort=") && !argument.begins_with("--ScholaPort=")) {
				continue;
			}
			const godot::String value = argument.get_slice("=", 1);
			const int64_t parsed = value.is_valid_int() ? value.to_int() : 0;
			if (parsed < MIN_PORT || parsed > MAX_PORT) {
				return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT,
						"The command-line argument " + std::string(argument.utf8().get_data()) +
								" is not a port number from 1 to 65535.");
			}
			r_port = static_cast<int32_t>(parsed);
			return schola::Status::ok();
		}
	}
	r_port = p_default;
	return schola::Status::ok();
}

} // namespace

ScholaTrainingConnector::ScholaTrainingConnector() = default;

ScholaTrainingConnector::~ScholaTrainingConnector() {
	loop.stop();
}

void ScholaTrainingConnector::set_port(int32_t p_port) {
	port = std::clamp(p_port, MIN_PORT, MAX_PORT);
}

int32_t ScholaTrainingConnector::get_port() const {
	return port;
}

void ScholaTrainingConnector::set_start_timeout_sec(double p_seconds) {
	start_timeout_sec = std::max(p_seconds, 0.0);
}

double ScholaTrainingConnector::get_start_timeout_sec() const {
	return start_timeout_sec;
}

void ScholaTrainingConnector::set_step_timeout_sec(double p_seconds) {
	step_timeout_sec = std::max(p_seconds, 0.0);
}

double ScholaTrainingConnector::get_step_timeout_sec() const {
	return step_timeout_sec;
}

bool ScholaTrainingConnector::is_training() const {
	return loop.is_running();
}

void ScholaTrainingConnector::_ready() {
	// Waiting for Python blocks the main thread, which would freeze the editor.
	set_physics_process(!godot::Engine::get_singleton()->is_editor_hint());
}

void ScholaTrainingConnector::_physics_process(double p_delta) {
	(void)p_delta;
	if (finished) {
		return;
	}
	// Starting here rather than in _ready() means every node's _ready() has
	// run before Python's first reset reaches the environments.
	if (!started) {
		start_session();
		return;
	}
	// Every later frame: wait for Python's next reset or step and run it.
	const schola::Status status = loop.tick(to_milliseconds(step_timeout_sec));
	if (!status.is_ok()) {
		finish(status);
	}
}

void ScholaTrainingConnector::_exit_tree() {
	if (loop.is_running()) {
		finish(schola::Status::error(schola::StatusCode::CLOSED,
				"ScholaTrainingConnector left the scene tree, so Godot closed the training session."));
	}
}

godot::Node *ScholaTrainingConnector::create_host() {
	// The host lives in the runtime extension. Creating it by class name keeps
	// this extension from linking against the runtime extension's C++ classes.
	godot::ClassDBSingleton *class_db = godot::ClassDBSingleton::get_singleton();
	if (!class_db->class_exists("ScholaTrainingHost")) {
		return nullptr;
	}
	godot::Node *host = godot::Object::cast_to<godot::Node>(static_cast<godot::Object *>(class_db->instantiate("ScholaTrainingHost")));
	if (host == nullptr) {
		return nullptr;
	}

	// Internal, so it doesn't show up as one of the scene's own children.
	host->set_name("ScholaTrainingHost");
	add_child(host, false, INTERNAL_MODE_FRONT);
	return host;
}

void ScholaTrainingConnector::start_session() {
	// One attempt per node: whatever happens below, never start again.
	started = true;

	// 1. Pick the port: -ScholaPort=<n> on the command line wins over the property.
	int32_t resolved_port = port;
	schola::Status status = resolve_port(port, resolved_port);
	if (!status.is_ok()) {
		finish(status);
		return;
	}

	// 2. Create the host that runs the scene's environments for us.
	godot::Node *host = create_host();
	if (host == nullptr) {
		finish(schola::Status::error(schola::StatusCode::FAILED_PRECONDITION,
				"ScholaTrainingHost is not available. Enable the Schola runtime add-on (addons/schola), which ScholaTrainingConnector needs."));
		return;
	}

	// 3. Wire Python (over gRPC) to the host, and wait for Python to connect.
	//    loop.start() blocks until Python has started the session and received
	//    the training definition, or until start_timeout_sec runs out.
	backend = std::make_unique<schola::HostTrainingBackend>(host);
	schola::GrpcConnectorSettings settings;
	settings.port = resolved_port;
	connector = std::make_unique<schola::GrpcConnector>(settings);

	godot::UtilityFunctions::print("Schola: waiting for Python to connect to ", to_godot_string(settings.address), ":", resolved_port, ".");
	status = loop.start(*connector, *backend, to_milliseconds(start_timeout_sec));
	if (!status.is_ok()) {
		finish(status);
	}
}

void ScholaTrainingConnector::finish(const schola::Status &p_status) {
	if (finished) {
		return;
	}
	finished = true;
	// Read this before stop(): a CLOSE from Python and a dropped connection
	// both arrive as CLOSED, and only the loop knows which one it was.
	const bool normal = loop.ended_normally();
	loop.stop();
	set_physics_process(false);

	// An empty error means Python finished on purpose.
	godot::String error;
	if (!normal) {
		error = to_godot_string(p_status.get_message());
		godot::UtilityFunctions::push_error("ScholaTrainingConnector: ", error);
	}
	emit_signal("training_finished", error);
}

void ScholaTrainingConnector::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("set_port", "port"), &ScholaTrainingConnector::set_port);
	godot::ClassDB::bind_method(godot::D_METHOD("get_port"), &ScholaTrainingConnector::get_port);
	godot::ClassDB::bind_method(godot::D_METHOD("set_start_timeout_sec", "seconds"), &ScholaTrainingConnector::set_start_timeout_sec);
	godot::ClassDB::bind_method(godot::D_METHOD("get_start_timeout_sec"), &ScholaTrainingConnector::get_start_timeout_sec);
	godot::ClassDB::bind_method(godot::D_METHOD("set_step_timeout_sec", "seconds"), &ScholaTrainingConnector::set_step_timeout_sec);
	godot::ClassDB::bind_method(godot::D_METHOD("get_step_timeout_sec"), &ScholaTrainingConnector::get_step_timeout_sec);
	godot::ClassDB::bind_method(godot::D_METHOD("is_training"), &ScholaTrainingConnector::is_training);

	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::INT, "port", godot::PROPERTY_HINT_RANGE, "1,65535"), "set_port", "get_port");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::FLOAT, "start_timeout_sec", godot::PROPERTY_HINT_RANGE, "0,600,0.1,or_greater,suffix:s"),
			"set_start_timeout_sec", "get_start_timeout_sec");
	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::FLOAT, "step_timeout_sec", godot::PROPERTY_HINT_RANGE, "0,600,0.1,or_greater,suffix:s"),
			"set_step_timeout_sec", "get_step_timeout_sec");
	ADD_SIGNAL(godot::MethodInfo("training_finished", godot::PropertyInfo(godot::Variant::STRING, "error")));
}
