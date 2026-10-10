// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace schola {
class Agent;
} // namespace schola

class ScholaSpace;

// Godot-facing config node for one agent
// When it has a ScholaEnvironment ancestor, that environment owns its training lifecycle
// A standalone agent is valid for local inference in a shipped game
class ScholaAgent : public godot::Node {
	GDCLASS(ScholaAgent, godot::Node)

public:
	// IDs must be unique within one environment
	// empty agent_id : use the godot node name
	// nonempty id : use configured value
	void set_agent_id(const godot::String &p_agent_id);
	godot::String get_agent_id() const;

	// Agents with the same nonempty type may share a training policy
	// empty agent_type : use this agent's resolved ID as its type
	// nonempty type : use configured value
	void set_agent_type(const godot::String &p_agent_type);
	godot::String get_agent_type() const;

	// observation and action spaces; these will be inspector resource fields
	// note: we use godot::Ref<T> to allow multiple agents to point to the same resource
	void set_observation_space(const godot::Ref<ScholaSpace> &p_observation_space);
	godot::Ref<ScholaSpace> get_observation_space() const;
	void set_action_space(const godot::Ref<ScholaSpace> &p_action_space);
	godot::Ref<ScholaSpace> get_action_space() const;
	// note: US5 does not duplicate Box, Discrete, bounds, points, validation logic from US2

	// returns the US1 core adapter while this node is in the scene tree
	// (ScholaAgent is the godot wrapper, schola::Agent is the US1 core abstraction)
	// the adapter is the same whether or not a ScholaEnvironment registers this agent for training
	schola::Agent *get_agent();
	const schola::Agent *get_agent() const;

	// warnings/errors; empty when the inspector and scene-tree configuration is valid
	godot::PackedStringArray get_configuration_errors() const;
	// 		-> might return: missing action space, invalid space definition, etc.
	godot::PackedStringArray _get_configuration_warnings() const override; // godot hook
	//		-> lets godot display config warning icon in editor inspector

protected:
	static void _bind_methods();

private:
	godot::String agent_id;
	// optional training-policy grouping label
	godot::String agent_type;
	godot::Ref<ScholaSpace> observation_space;
	godot::Ref<ScholaSpace> action_space;
};
