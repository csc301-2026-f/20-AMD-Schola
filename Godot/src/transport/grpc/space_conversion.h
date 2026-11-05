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

// Converts spaces and points to and from Python Schola's protobuf messages.

/** Infinite bounds leave low/high unset. */
void space_to_proto(const Space &p_space, ::Schola::Space &r_message);

/** INCOMPATIBLE for Text or an unknown dtype; INVALID_DATA for an unset or invalid space. */
Status proto_to_space(const ::Schola::Space &p_message, Space &r_space);

/** Uses p_space for BoxPoint shape and dtype. */
void point_to_proto(const Point &p_point, const Space &p_space, ::Schola::Point &r_message);

/** Validates against p_space. INCOMPATIBLE for Text; INVALID_ARGUMENT if the point does not fit. */
Status proto_to_point(const ::Schola::Point &p_message, const Space &p_space, Point &r_point);

/** Decodes a point without space validation (Python validates training actions). */
Status proto_to_point(const ::Schola::Point &p_message, Point &r_point);

void interaction_definition_to_proto(const InteractionDefinition &p_definition, ::Schola::AgentDefinition &r_message);
Status proto_to_interaction_definition(const ::Schola::AgentDefinition &p_message, InteractionDefinition &r_definition);

void agent_state_to_proto(const AgentState &p_state, const Space &p_observation_space, ::Schola::AgentState &r_message);
Status proto_to_agent_state(const ::Schola::AgentState &p_message, const Space &p_observation_space, AgentState &r_state);

} //namespace schola
