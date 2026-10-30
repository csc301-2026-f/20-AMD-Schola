// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/lifecycle/environment_coordinator.h"

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <cstdint>
#include <optional>
#include <vector>

class ScholaEnvironment;

class ScholaTrainingHost : public godot::Node {
	GDCLASS(ScholaTrainingHost, godot::Node)

public:
	godot::Dictionary initialize_session();
	godot::Dictionary set_autoreset_mode(int64_t p_mode);
	godot::Dictionary define();
	godot::Dictionary reset(const godot::Dictionary &p_request);
	godot::Dictionary step(const godot::Dictionary &p_request);
	godot::Dictionary close();
	void _exit_tree() override;

protected:
	static void _bind_methods();

private:
	enum class SessionState {
		CONFIGURING,
		ACTIVE,
		SHUTTING_DOWN,
		CLOSED,
	};

	schola::Status initialize_session_core();
	schola::Status require_active_session() const;
	static schola::Status require_main_thread();
	schola::Status validate_environment_nodes() const;
	schola::Status fail_session(const schola::Status &p_failure);
	schola::Status handle_coordinator_result(const schola::Status &p_status);
	schola::Status shutdown_core();

	std::vector<godot::ObjectID> environment_ids;
	schola::EnvironmentCoordinator coordinator;
	std::optional<schola::TrainingDefinition> training_definition;
	SessionState session_state = SessionState::CONFIGURING;
};
