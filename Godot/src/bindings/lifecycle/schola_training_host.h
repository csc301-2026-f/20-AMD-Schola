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

/**
 * Godot-facing owner of one fixed training session.
 *
 * The host discovers ScholaEnvironment descendants in scene-tree order and
 * assigns contiguous environment IDs for the lifetime of the session. It owns
 * the EnvironmentCoordinator but not the Godot environment nodes. All public
 * operations must run on Godot's main thread. A missing environment or a
 * coordinator failure closes the entire session rather than remapping IDs or
 * publishing partial output.
 *
 * Bound methods return a Dictionary with `status` and `value` entries. The
 * status contains integer `code` and String `message` fields; `value` is
 * null on failure.
 */
class ScholaTrainingHost : public godot::Node {
	GDCLASS(ScholaTrainingHost, godot::Node)

public:
	/** Discovers and validates the session's fixed environment set. */
	godot::Dictionary initialize_session();
	/** Sets the AutoResetMode before define() initializes the environments. */
	godot::Dictionary set_autoreset_mode(int64_t p_mode);
	/** Initializes the environments and returns their ordered definitions. */
	godot::Dictionary define();
	/** Resets every environment using optional settings keyed by environment ID. */
	godot::Dictionary reset(const godot::Dictionary &p_request);
	/** Steps every environment using one agent-action dictionary per environment. */
	godot::Dictionary step(const godot::Dictionary &p_request);
	/** Idempotently closes the coordinator and training session. */
	godot::Dictionary close();
	/** Closes the session when the host leaves the scene tree. */
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
