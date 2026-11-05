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
#include <set>
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
	// Possible definitions are captured once; live nodes are rediscovered every operation.
	if (initialized) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "initialize() was already called");
	}

	// The node already knows how to spot a broken scene (no agents, missing
	// spaces, and so on), so reuse its checks instead of repeating them.
	const godot::PackedStringArray errors = node->get_configuration_errors();
	if (!errors.is_empty()) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, to_std_string(godot::String("; ").join(errors)));
	}

	const godot::TypedArray<ScholaAgent> agent_nodes = node->get_possible_agents();
	if (agent_nodes.is_empty()) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "add a ScholaAgent node below this environment");
	}

	// Build everything in local variables first, so a failure part way
	// through leaves this adapter and the caller's map untouched.
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

		definitions.emplace(id, std::move(definition));
	}

	// Everything passed. Commit, then hand the definitions to the caller.
	this->definitions = definitions;
	initialized = true;
	r_agents = std::move(definitions);
	return schola::Status::ok();
}

schola::Status GodotEnvironmentAdapter::collect_current_agents(std::vector<AgentEntry> &r_agents) const {
	std::set<schola::AgentId> seen;
	const auto nodes = node->get_agents();
	for (int32_t i = 0; i < nodes.size(); ++i) {
		godot::Object *object = nodes[i];
		auto *agent = godot::Object::cast_to<ScholaAgent>(object);
		if (agent == nullptr || agent->is_queued_for_deletion()) {
			continue;
		}
		const auto id = to_std_string(agent->get_agent_id());
		const auto declared = definitions.find(id);
		if (declared == definitions.end() || !seen.insert(id).second) {
			return agent_error(id, schola::StatusCode::INVALID_DATA, "agent ID must be declared and unique");
		}
		schola::InteractionDefinition definition;
		auto status = agent->get_agent()->define(definition);
		if (!status.is_ok()) {
			return status;
		}
		if (definition.observation_space != declared->second.observation_space ||
				definition.action_space != declared->second.action_space || definition.agent_type != declared->second.agent_type) {
			return agent_error(id, schola::StatusCode::INCOMPATIBLE, "spawned agent differs from its declared definition");
		}
		r_agents.push_back({ id, godot::ObjectID(agent->get_instance_id()) });
	}
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

	std::vector<AgentEntry> current;
	auto collect_status = collect_current_agents(current);
	if (!collect_status.is_ok()) {
		return collect_status;
	}
	last_states.clear();

	// Read every active agent's first observation of the fresh episode.
	std::map<schola::AgentId, schola::InitialAgentState> states;
	for (const AgentEntry &entry : current) {
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
		last_states.emplace(entry.id, schola::AgentState{ state.observation, 0.0f, false, false, state.info });
		states.emplace(entry.id, std::move(state));
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

	std::vector<AgentEntry> current;
	auto status = collect_current_agents(current);
	if (!status.is_ok()) {
		return status;
	}
	// Validate the full request before invoking any gameplay hooks.
	size_t active_count = 0;
	for (const auto &[id, previous] : last_states) {
		if (!previous.terminated && !previous.truncated) {
			++active_count;
			const auto action = p_actions.find(id);
			if (action == p_actions.end()) {
				return agent_error(id, schola::StatusCode::INVALID_ARGUMENT, "missing action");
			}
			status = definitions.at(id).action_space.validate(action->second);
			if (!status.is_ok()) {
				return status;
			}
		}
	}
	if (p_actions.size() != active_count) {
		return environment_error(node, schola::StatusCode::INVALID_ARGUMENT, "actions must name exactly the active agents");
	}
	if (!p_actions.empty() && !GDVIRTUAL_IS_OVERRIDDEN_PTR(node, _get_reward)) {
		return environment_error(node, schola::StatusCode::FAILED_PRECONDITION, "_get_reward() is not overridden");
	}
	for (const auto &entry : current) {
		const auto action = p_actions.find(entry.id);
		if (action == p_actions.end()) {
			continue;
		}
		ScholaAgent *agent = nullptr;
		status = find_agent_node(entry.id, entry.node_id, agent);
		// Another agent may have removed this one during its action.
		if (!status.is_ok() || agent->is_queued_for_deletion() || !node->is_ancestor_of(agent)) {
			continue;
		}
		status = agent->get_agent()->act(action->second);
		if (!status.is_ok()) {
			return status;
		}
	}
	current.clear();
	status = collect_current_agents(current);
	if (!status.is_ok()) {
		return status;
	}
	std::map<schola::AgentId, schola::AgentState> states;
	for (const auto &entry : current) {
		const auto previous = last_states.find(entry.id);
		if (previous != last_states.end() && (previous->second.terminated || previous->second.truncated)) {
			continue; // An ID is retired until the next environment reset.
		}
		ScholaAgent *agent = nullptr;
		status = find_agent_node(entry.id, entry.node_id, agent);
		if (!status.is_ok() || agent->is_queued_for_deletion() || !node->is_ancestor_of(agent)) {
			continue;
		}
		schola::AgentState state;
		status = agent->get_agent()->observe(state.observation);
		if (!status.is_ok()) {
			return status;
		}
		if (previous != last_states.end()) {
			double reward = 0.0;
			if (!GDVIRTUAL_CALL_PTR(node, _get_reward, agent, reward)) {
				return agent_error(entry.id, schola::StatusCode::FAILED_PRECONDITION, "_get_reward() could not be called");
			}
			state.reward = static_cast<float>(reward);
			GDVIRTUAL_CALL_PTR(node, _is_terminated, agent, state.terminated);
			GDVIRTUAL_CALL_PTR(node, _is_truncated, agent, state.truncated);
		}
		godot::Dictionary info;
		GDVIRTUAL_CALL_PTR(node, _get_info, agent, info);
		status = to_info(info, state.info);
		if (!status.is_ok()) {
			return status;
		}
		states.emplace(entry.id, std::move(state));
	}
	for (const auto &[id, previous] : last_states) {
		if (!previous.terminated && !previous.truncated && states.count(id) == 0) {
			auto terminal = previous;
			terminal.reward = 0.0f;
			terminal.terminated = true;
			states.emplace(id, std::move(terminal));
		}
	}
	for (const auto &[id, state] : states) {
		last_states[id] = state;
	}
	++episode_step;
	r_states = std::move(states);
	const bool all_finished = std::all_of(last_states.begin(), last_states.end(), [](const auto &entry) {
		return entry.second.terminated || entry.second.truncated;
	});
	if (all_finished) {
		episode_active = false;
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
	std::vector<AgentEntry> current;
	auto collected = collect_current_agents(current);
	if (!collected.is_ok()) {
		return collected;
	}
	for (const AgentEntry &entry : current) {
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
