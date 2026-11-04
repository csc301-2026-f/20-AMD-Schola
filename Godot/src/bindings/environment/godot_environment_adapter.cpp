// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/environment/godot_environment_adapter.h"

#include "bindings/environment/schola_agent.h"
#include "bindings/environment/schola_environment.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <algorithm>
#include <cstdint>
#include <string>
#include <utility>

namespace {

std::string to_std_string(const godot::String &p_string) {
	return p_string.utf8().get_data();
}

// Prefixes every message with the environment node's name so failures say
// which environment broke.
schola::Status environment_error(const ScholaEnvironment *p_node, schola::StatusCode p_code, const std::string &p_message) {
	const std::string name = to_std_string(godot::String(p_node->get_name()));
	return schola::Status::error(p_code, "Environment '" + name + "': " + p_message);
}

// Same prefix GodotAgentAdapter uses, so every agent failure reads alike.
schola::Status agent_error(const schola::AgentId &p_id, schola::StatusCode p_code, const std::string &p_message) {
	return schola::Status::error(p_code, "Agent '" + p_id + "': " + p_message);
}

// Looks an agent node up by its Godot instance ID. ObjectDB returns null once
// Godot has freed the node, so this never hands back a dangling pointer.
schola::Status find_agent_node(const schola::AgentId &p_id, godot::ObjectID p_node_id, ScholaAgent *&r_node) {
	godot::Object *object = godot::ObjectDB::get_instance(static_cast<uint64_t>(p_node_id));
	ScholaAgent *agent_node = godot::Object::cast_to<ScholaAgent>(object);
	if (agent_node == nullptr) {
		return agent_error(p_id, schola::StatusCode::FAILED_PRECONDITION, "the agent node was freed");
	}
	r_node = agent_node;
	return schola::Status::ok();
}

// Reset options arrive as std::strings; _reset_episode() takes a Dictionary.
godot::Dictionary to_dictionary(const std::map<std::string, std::string> &p_options) {
	godot::Dictionary dictionary;
	for (const auto &[key, value] : p_options) {
		dictionary[godot::String::utf8(key.c_str())] = godot::String::utf8(value.c_str());
	}
	return dictionary;
}

bool is_text(const godot::Variant &p_value) {
	return p_value.get_type() == godot::Variant::STRING || p_value.get_type() == godot::Variant::STRING_NAME;
}

// _get_info() must return String keys and String values, because Python
// receives info as a map of strings. Anything else is rejected rather than
// silently stringified.
schola::Status to_info(const godot::Dictionary &p_dictionary, std::map<std::string, std::string> &r_info) {
	std::map<std::string, std::string> info;
	const godot::Array keys = p_dictionary.keys();
	for (int32_t index = 0; index < keys.size(); ++index) {
		const godot::Variant key = keys[index];
		const godot::Variant value = p_dictionary.get(key, godot::Variant());
		if (!is_text(key) || !is_text(value)) {
			return schola::Status::error(schola::StatusCode::INVALID_ARGUMENT, "info keys and values must be Strings");
		}
		info[to_std_string(godot::String(key))] = to_std_string(godot::String(value));
	}
	r_info = std::move(info);
	return schola::Status::ok();
}

} // namespace

GodotEnvironmentAdapter::GodotEnvironmentAdapter(ScholaEnvironment *p_node) :
		node(p_node) {}

schola::Status GodotEnvironmentAdapter::initialize(std::map<schola::AgentId, schola::InteractionDefinition> &r_agents) {
	// The agent set is fixed after the first success, so a second call is a
	// caller bug rather than a refresh.
	if (initialized) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "initialize() was already called");
	}

	// The node already knows how to spot a broken scene (no agents, missing
	// spaces, and so on), so reuse its checks instead of repeating them.
	const godot::PackedStringArray errors = node->get_configuration_errors();
	if (!errors.is_empty()) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, to_std_string(godot::String("; ").join(errors)));
	}

	const godot::TypedArray<ScholaAgent> agent_nodes = node->get_agents();
	if (agent_nodes.is_empty()) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "add a ScholaAgent node below this environment");
	}

	// Build everything in local variables first, so a failure part way
	// through leaves this adapter and the caller's map untouched.
	std::vector<AgentEntry> new_agents;
	std::map<schola::AgentId, schola::InteractionDefinition> definitions;
	for (int32_t index = 0; index < agent_nodes.size(); ++index) {
		godot::Object *agent_object = agent_nodes[index];
		ScholaAgent *agent_node = godot::Object::cast_to<ScholaAgent>(agent_object);
		if (agent_node == nullptr) {
			continue;
		}

		// Two agents with the same ID would overwrite each other in every map
		// Python sees, so refuse the whole environment.
		const schola::AgentId id = to_std_string(agent_node->get_agent_id());
		if (definitions.count(id) != 0) {
			return agent_error(id, schola::StatusCode::FAILED_PRECONDITION, "agent_id is used by more than one agent");
		}

		// Each agent reads its own Inspector spaces. Its error already names
		// the agent, so pass it straight through.
		schola::InteractionDefinition definition;
		const schola::Status status = agent_node->get_agent()->define(definition);
		if (!status.is_ok()) {
			return status;
		}

		AgentEntry entry;
		entry.id = id;
		entry.node_id = godot::ObjectID(agent_node->get_instance_id());
		entry.action_space = definition.action_space;
		new_agents.push_back(std::move(entry));
		definitions.emplace(id, std::move(definition));
	}

	// Everything passed. Commit, then hand the definitions to the caller.
	agents = std::move(new_agents);
	initialized = true;
	r_agents = std::move(definitions);
	return schola::Status::ok();
}

schola::Status GodotEnvironmentAdapter::reset(const schola::ResetSettings &p_settings,
		std::map<schola::AgentId, schola::InitialAgentState> &r_states) {
	if (!initialized) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "reset() called before initialize()");
	}

	// Whatever happens below, the previous episode is over. If this reset
	// fails, step() must refuse to run until a reset succeeds.
	episode_active = false;

	// Seed the environment's RNG only when Python sent a seed. Without one,
	// the RNG keeps running from where it was, as ResetSettings describes.
	if (p_settings.seed.has_value()) {
		const godot::Ref<godot::RandomNumberGenerator> rng = node->get_rng();
		if (rng.is_null()) {
			return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "get_rng() returned null, so the seed cannot be applied");
		}
		rng->set_seed(static_cast<uint64_t>(*p_settings.seed));
	}

	// _reset_episode() gets the seed as an int, or null when there is none,
	// so the script can tell the two apart. Overriding it is optional: a
	// scene with nothing to put back can leave it out.
	const godot::Variant seed = p_settings.seed.has_value() ? godot::Variant(static_cast<int64_t>(*p_settings.seed)) : godot::Variant();
	GDVIRTUAL_CALL_PTR(node, _reset_episode, seed, to_dictionary(p_settings.options));

	// Read every agent's first observation of the fresh episode.
	std::map<schola::AgentId, schola::InitialAgentState> states;
	for (const AgentEntry &entry : agents) {
		ScholaAgent *agent_node = nullptr;
		schola::Status status = find_agent_node(entry.id, entry.node_id, agent_node);
		if (!status.is_ok()) {
			return status;
		}

		schola::InitialAgentState state;
		status = agent_node->get_agent()->observe(state.observation);
		if (!status.is_ok()) {
			return status;
		}
		states.emplace(entry.id, std::move(state));
	}

	// Everything passed. Every agent is back in the episode.
	for (AgentEntry &entry : agents) {
		entry.finished = false;
	}
	episode_active = true;
	episode_step = 0;
	r_states = std::move(states);
	node->emit_signal("episode_started");
	return schola::Status::ok();
}

schola::Status GodotEnvironmentAdapter::step(const std::map<schola::AgentId, schola::Point> &p_actions,
		std::map<schola::AgentId, schola::AgentState> &r_states) {
	if (!initialized || !episode_active) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "step() called before reset()");
	}

	// Phase 1: check every action before anything moves.
	for (const auto &[id, action] : p_actions) {
		// C++17 lambdas cannot capture a structured binding, so name it first.
		const schola::AgentId &wanted_id = id;
		const auto entry = std::find_if(agents.begin(), agents.end(), [&wanted_id](const AgentEntry &p_entry) {
			return p_entry.id == wanted_id;
		});
		if (entry == agents.end()) {
			return agent_error(id, schola::StatusCode::NOT_FOUND, "not part of this environment");
		}
		if (entry->finished) {
			return agent_error(id, schola::StatusCode::FAILED_PRECONDITION, "already finished this episode");
		}
		const schola::Status status = entry->action_space.validate(action);
		if (!status.is_ok()) {
			return agent_error(id, status.get_code(), "rejected action: " + status.get_message());
		}
	}

	// A missing _get_reward() would otherwise only show up after every agent
	// had already acted, so catch it here while the world is still untouched.
	if (!p_actions.empty() && !GDVIRTUAL_IS_OVERRIDDEN_PTR(node, _get_reward)) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "_get_reward() is not overridden");
	}

	// Line the actions up in scene-tree order, so agents always act in the
	// order they appear in the editor, and make sure every node still exists.
	struct PendingAgent {
		AgentEntry *entry = nullptr;
		const schola::Point *action = nullptr;
		bool finished = false;
	};
	std::vector<PendingAgent> pending;
	for (AgentEntry &entry : agents) {
		const auto action = p_actions.find(entry.id);
		if (action == p_actions.end()) {
			continue;
		}
		ScholaAgent *agent_node = nullptr;
		const schola::Status status = find_agent_node(entry.id, entry.node_id, agent_node);
		if (!status.is_ok()) {
			return status;
		}
		pending.push_back({ &entry, &action->second });
	}

	// Phase 2a: every agent acts. The world starts changing here, so any
	// failure from now on means the caller should end the session. Nodes are
	// looked up again each time, since a script may free one mid-step.
	for (const PendingAgent &item : pending) {
		ScholaAgent *agent_node = nullptr;
		schola::Status status = find_agent_node(item.entry->id, item.entry->node_id, agent_node);
		if (!status.is_ok()) {
			return status;
		}
		status = agent_node->get_agent()->act(*item.action);
		if (!status.is_ok()) {
			return status;
		}
	}

	// Phase 2b: once everyone has acted, read back each agent's result, so
	// every observation sees the same world.
	std::map<schola::AgentId, schola::AgentState> states;
	for (PendingAgent &item : pending) {
		const schola::AgentId &id = item.entry->id;
		ScholaAgent *agent_node = nullptr;
		schola::Status status = find_agent_node(id, item.entry->node_id, agent_node);
		if (!status.is_ok()) {
			return status;
		}

		schola::AgentState state;
		status = agent_node->get_agent()->observe(state.observation);
		if (!status.is_ok()) {
			return status;
		}

		// _get_reward() was checked in phase 1, so false here means the
		// script call itself failed, for example a wrong argument count.
		double reward = 0.0;
		if (!GDVIRTUAL_CALL_PTR(node, _get_reward, agent_node, reward)) {
			return agent_error(id, schola::StatusCode::FAILED_PRECONDITION, "_get_reward() could not be called");
		}
		state.reward = static_cast<float>(reward);

		// These are optional. Left unoverridden, the call does nothing and the
		// values keep their defaults: false, false and an empty Dictionary.
		GDVIRTUAL_CALL_PTR(node, _is_terminated, agent_node, state.terminated);
		GDVIRTUAL_CALL_PTR(node, _is_truncated, agent_node, state.truncated);
		godot::Dictionary info;
		GDVIRTUAL_CALL_PTR(node, _get_info, agent_node, info);
		status = to_info(info, state.info);
		if (!status.is_ok()) {
			return agent_error(id, status.get_code(), "_get_info() returned a bad value: " + status.get_message());
		}

		item.finished = state.terminated || state.truncated;
		states.emplace(id, std::move(state));
	}

	// Everything passed. Record who finished, and announce the end of the
	// episode only on the step that finished the last agent.
	bool finished_this_step = false;
	for (const PendingAgent &item : pending) {
		if (item.finished) {
			item.entry->finished = true;
			finished_this_step = true;
		}
	}
	const bool all_finished = std::all_of(agents.begin(), agents.end(), [](const AgentEntry &p_entry) {
		return p_entry.finished;
	});
	++episode_step;
	r_states = std::move(states);
	if (finished_this_step && all_finished) {
		node->emit_signal("episode_ended");
	}
	return schola::Status::ok();
}

schola::Status GodotEnvironmentAdapter::get_agents(std::vector<schola::Agent *> &r_agents) const {
	if (!initialized) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "get_agents() called before initialize()");
	}

	// Build the list locally, so a freed agent leaves the caller's vector
	// untouched.
	std::vector<schola::Agent *> result;
	result.reserve(agents.size());
	for (const AgentEntry &entry : agents) {
		ScholaAgent *agent_node = nullptr;
		const schola::Status status = find_agent_node(entry.id, entry.node_id, agent_node);
		if (!status.is_ok()) {
			return status;
		}
		result.push_back(agent_node->get_agent());
	}

	r_agents = std::move(result);
	return schola::Status::ok();
}

int64_t GodotEnvironmentAdapter::get_episode_step() const {
	return episode_step;
}
