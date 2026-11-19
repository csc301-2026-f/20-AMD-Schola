// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

// Dependency on US4
#if !__has_include("core/lifecycle/training_backend.h")
#error "US3 needs TrainingBackend from core/lifecycle/training_backend.h"
#endif

#include "core/lifecycle/training_backend.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/object_id.hpp>

#include <optional>

namespace schola {

/**
 * Implements TrainingBackend by calling the bound methods of the
 * US4-owned ScholaTrainingHost node using Variant arguments. US4 owns the
 * host implementation and its EnvironmentCoordinator.
 *
 * The training extension never calls the runtime extension's C++ classes
 * directly, so a shipped game can drop the training extension entirely.
 * Points cross as Variants, and spaces as the Dictionaries the host's define()
 * returns. Every method must be called on the Godot main thread.
 *
 * The host's own errors pass through unchanged. A reply the host should never
 * send fails with INVALID_DATA naming the host method. Every failure leaves
 * the output untouched.
 */
class HostTrainingBackend final : public TrainingBackend {
public:
	// p_host is not owned. Each call looks it up again, so a freed host fails
	// with FAILED_PRECONDITION instead of being used after it is freed.
	explicit HostTrainingBackend(godot::Object *p_host);

	// Calls initialize_session() first, so a scene that cannot be trained
	// fails here and Python receives the error as its StartGymConnector reply.
	Status set_autoreset_mode(AutoResetMode p_mode) override;

	// Also keeps the definition: reset() and step() need its observation
	// spaces to read the host's observations back.
	Status define(TrainingDefinition &r_definition) override;

	Status reset(const ResetRequest &p_request, InitialState &r_initial_state) override;
	Status step(const StepRequest &p_request, StepResult &r_result) override;

	// Succeeds without a call if the host was already freed.
	Status close() override;

private:
	godot::ObjectID host_id;
	std::optional<TrainingDefinition> definition;
};

} // namespace schola
