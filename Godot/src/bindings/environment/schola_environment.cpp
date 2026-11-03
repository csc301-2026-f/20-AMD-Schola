// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/schola_environment.h"

#include "bindings/environment/godot_environment_adapter.h"

#include <godot_cpp/core/class_db.hpp>

#include <memory>

namespace {

void collect_agents(const godot::Node *p_node, godot::TypedArray<ScholaAgent> &r_agents) {
	const godot::TypedArray<godot::Node> children = p_node->get_children();
	for (int32_t index = 0; index < children.size(); ++index) {
		godot::Object *child_object = children[index];
		godot::Node *child = godot::Object::cast_to<godot::Node>(child_object);
		if (child == nullptr) {
			continue;
		}
		if (godot::Object::cast_to<ScholaEnvironment>(child) != nullptr) {
			continue;
		}
		if (ScholaAgent *agent = godot::Object::cast_to<ScholaAgent>(child)) {
			r_agents.push_back(agent);
		}
		collect_agents(child, r_agents);
	}
}

} // namespace

ScholaEnvironment::ScholaEnvironment() {
	// Create the RNG up front so get_rng() never returns null, even before
	// the first reset. Godot gives a new RandomNumberGenerator a random seed,
	// so runs differ until Python sends a seed.
	rng.instantiate();
}

// Empty, but it has to live here: destroying the unique_ptr needs the full
// GodotEnvironmentAdapter definition, which the header only forward-declares.
ScholaEnvironment::~ScholaEnvironment() = default;

int64_t ScholaEnvironment::get_episode_step() const {
	// The adapter does the stepping, so it keeps the count. Before anything
	// has asked for the adapter, no episode has run.
	return environment_adapter ? environment_adapter->get_episode_step() : 0;
}

godot::Ref<godot::RandomNumberGenerator> ScholaEnvironment::get_rng() const {
	return rng;
}

schola::Environment *ScholaEnvironment::get_environment() {
	// The adapter walks the scene tree to find agents, so it is only handed
	// out while this node is in one.
	if (!is_inside_tree()) {
		return nullptr;
	}

	// Create the adapter the first time someone asks for it. It keeps a
	// pointer back to this node, which is safe because this node owns it
	// and deletes it when the node itself is destroyed.
	if (!environment_adapter) {
		environment_adapter = std::make_unique<GodotEnvironmentAdapter>(this);
	}
	return environment_adapter.get();
}

const schola::Environment *ScholaEnvironment::get_environment() const {
	// Same adapter as above. const_cast lets this read-only version reuse it
	// instead of duplicating the creation logic.
	return const_cast<ScholaEnvironment *>(this)->get_environment();
}

godot::TypedArray<ScholaAgent> ScholaEnvironment::get_agents() const {
	godot::TypedArray<ScholaAgent> agents;
	collect_agents(this, agents);
	return agents;
}

godot::PackedStringArray ScholaEnvironment::get_configuration_errors() const {
	godot::PackedStringArray errors;
	const godot::TypedArray<ScholaAgent> agents = get_agents();
	if (agents.is_empty()) {
		errors.append("Add a ScholaAgent node below this environment.");
	}
	for (int32_t index = 0; index < agents.size(); ++index) {
		godot::Object *agent_object = agents[index];
		ScholaAgent *agent = godot::Object::cast_to<ScholaAgent>(agent_object);
		if (agent == nullptr) {
			continue;
		}
		const godot::PackedStringArray agent_errors = agent->get_configuration_errors();
		for (int32_t error_index = 0; error_index < agent_errors.size(); ++error_index) {
			const godot::String error = agent_errors[error_index];
			errors.append("Agent '" + agent->get_resolved_agent_id() + "': " + error);
		}
	}
	return errors;
}

godot::PackedStringArray ScholaEnvironment::_get_configuration_warnings() const {
	return get_configuration_errors();
}

void ScholaEnvironment::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("get_agents"), &ScholaEnvironment::get_agents);
	godot::ClassDB::bind_method(godot::D_METHOD("get_configuration_errors"), &ScholaEnvironment::get_configuration_errors);
	godot::ClassDB::bind_method(godot::D_METHOD("get_episode_step"), &ScholaEnvironment::get_episode_step);
	godot::ClassDB::bind_method(godot::D_METHOD("get_rng"), &ScholaEnvironment::get_rng);
	ADD_SIGNAL(godot::MethodInfo("episode_started"));
	ADD_SIGNAL(godot::MethodInfo("episode_ended"));
	GDVIRTUAL_BIND(_reset_episode, "seed", "options");
	GDVIRTUAL_BIND(_get_step_result, "agent");
}
