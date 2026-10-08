// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/lifecycle/training_types.h"

#include <functional>

namespace schola {

// StepResult is valid only when Status is OK. The backend invokes a retained
// completion exactly once, including when close() cancels a pending step.
using StepCompletion = std::function<void(Status, StepResult)>;

// Logical lifecycle boundary used by the connector. The connector calls every
// method serially on the backend's owning thread. A step completes only after
// its actions have crossed the required physics boundary. Synchronous output
// parameters remain unchanged whenever an operation returns a non-OK Status.
// The Godot-facing training host implements this contract around an
// EnvironmentCoordinator; US3 depends only on this interface and may provide a
// proxy or fake without depending on Godot lifecycle internals.
class TrainingBackend {
public:
	virtual ~TrainingBackend() = default;

	// Initializes the fixed training session and returns its definition.
	virtual Status define(TrainingDefinition &r_definition) = 0;

	// Called exactly once after define() and before reset() or step().
	virtual Status set_autoreset_mode(AutoResetMode p_mode) = 0;

	// Performs an explicit reset synchronously on the owning thread.
	virtual Status reset(const ResetRequest &p_request, InitialState &r_initial_state) = 0;

	// Takes ownership of the request data needed after this call. A successful
	// submission invokes p_on_complete exactly once after state collection, on
	// the owning thread. If submission fails, the callback is not retained or
	// invoked. A second step is rejected while one is pending.
	virtual Status step(StepRequest p_request, StepCompletion p_on_complete) = 0;

	// Rejects new operations. A pending step is completed exactly once with a
	// CLOSED status and an empty StepResult before close() returns.
	virtual Status close() = 0;
};

} // namespace schola
