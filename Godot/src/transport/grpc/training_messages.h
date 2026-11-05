// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

// Dependency on the US3 gRPC/Protocol Buffers compatibility spike
#if !__has_include("GymConnector.pb.h")
#error "US3 needs Protocol Buffer bindings generated into Godot/generated/proto/"
#endif

#include "core/connector/connector.h"

#include "Definitions.pb.h"
#include "GymConnector.pb.h"
#include "State.pb.h"
#include "StateUpdates.pb.h"
#include <grpcpp/support/status.h>

#include <string_view>

namespace schola {

// Converts the GymService messages. Spaces and points inside them use US2's
// protobuf conversions, which need each point's space. That is why the
// state and update conversions take the TrainingDefinition published at
// startup.

/**
 * StartGymConnector request.
 *
 * Out: INVALID_ARGUMENT naming the value if autoreset_type is not one this
 *      build recognizes, for example one sent by a newer Python client.
 */
Status from_proto(const ::Schola::GymConnectorStartRequest &p_message, StartRequest &r_request);

/** RequestTrainingDefinition reply. */
void to_proto(const TrainingDefinition &p_definition, ::Schola::TrainingDefinition &r_message);

/**
 * UpdateState request. Each action is read with its agent's action space
 * from p_definition, which also checks that it fits that space.
 *
 * Out: Python's CLOSED status becomes UpdateKind::CLOSE. Its ERROR status
 *      (or any status this build does not know) returns CLOSED.
 *      INVALID_ARGUMENT if the message has neither a reset nor a step, or an
 *      action does not fit its space. NOT_FOUND for an action addressed to an
 *      environment or agent that is not in p_definition.
 */
Status from_proto(const ::Schola::StateUpdate &p_message, const TrainingDefinition &p_definition, ConnectorUpdate &r_update);

/**
 * UpdateState reply after a reset.
 *
 * Out: NOT_FOUND if a state names an environment or agent that is not in
 *      p_definition.
 */
Status to_proto(const InitialState &p_initial_state, const TrainingDefinition &p_definition, ::Schola::State &r_message);

/**
 * UpdateState reply after a step. initial_state is only sent when an
 * environment auto-reset, because Python checks whether it is present.
 *
 * Out: NOT_FOUND if a state names an environment or agent that is not in
 *      p_definition.
 */
Status to_proto(const StepResult &p_result, const TrainingDefinition &p_definition, ::Schola::State &r_message);

/**
 * Converts a Status into the gRPC status Python receives, prefixing the
 * message with p_rpc so Python's error names the call that failed.
 *
 * OK stays OK. Otherwise:
 *   INVALID_ARGUMENT, INVALID_DATA -> INVALID_ARGUMENT
 *   NOT_FOUND                      -> NOT_FOUND
 *   FAILED_PRECONDITION            -> FAILED_PRECONDITION
 *   INCOMPATIBLE                   -> FAILED_PRECONDITION
 *   TIMEOUT                        -> DEADLINE_EXCEEDED
 *   CLOSED                         -> UNAVAILABLE
 *   RUNTIME_FAILURE                -> INTERNAL
 */
grpc::Status to_grpc_status(const Status &p_status, std::string_view p_rpc);

} // namespace schola
