// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

// Cannot be built or run until US3 generates protobuf bindings
#if !__has_include("Spaces.pb.h")
#error "US2 protobuf conversion needs Protocol Buffer bindings generated into Godot/generated/proto/"
#endif

#include "core/common/status.h"
#include "core/environment/environment.h"
#include "core/environment/interaction_definition.h"
#include "core/spaces/point.h"
#include "core/spaces/space.h"

#include "Definitions.pb.h"
#include "Points.pb.h"
#include "Spaces.pb.h"
#include "State.pb.h"

namespace schola {

// Converts US2 spaces and points to and from the protobuf messages Python Schola uses.
// US3's message conversion calls these for every space and point it sends or receives.

/** Infinite Box bounds leave low/high unset. */
void space_to_proto(const Space &p_space, ::Schola::Space &r_message);

/**
 * Out: INCOMPATIBLE for a Text space or an unknown dtype. INVALID_DATA for an
 *      unset space or a definition that fails Space::check_definition().
 */
Status proto_to_space(const ::Schola::Space &p_message, Space &r_space);

/** Uses p_space for BoxPoint shape and dtype. */
void point_to_proto(const Point &p_point, const Space &p_space, ::Schola::Point &r_message);

/**
 * Builds Dict entries in p_space order and validates the result against p_space.
 *
 * Out: INCOMPATIBLE for a Text point. INVALID_ARGUMENT for an unset point, a
 *      kind or Dict key mismatch, or a point that fails Space::validate().
 */
Status proto_to_point(const ::Schola::Point &p_message, const Space &p_space, Point &r_point);

void interaction_definition_to_proto(const InteractionDefinition &p_definition, ::Schola::AgentDefinition &r_message);
Status proto_to_interaction_definition(const ::Schola::AgentDefinition &p_message, InteractionDefinition &r_definition);

void agent_state_to_proto(const AgentState &p_state, const Space &p_observation_space, ::Schola::AgentState &r_message);
Status proto_to_agent_state(const ::Schola::AgentState &p_message, const Space &p_observation_space, AgentState &r_state);

}
