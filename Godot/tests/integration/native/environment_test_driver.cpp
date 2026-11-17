// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

// Test-only bridge so GdUnit4 exercises the actual C++ Environment interface.
// Compiled and registered only with integration_tests=yes.
#include "bindings/environment/schola_agent.h"
#include "bindings/environment/schola_environment.h"
#include "core/environment/environment.h"
#include "core/spaces/point.h"
#include "interop/variant_conversion.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <cstdint>
#include <map>
#include <string>
#include <utility>
#include <vector>

// Every call pre-fills its output with a "sentinel" entry. The adapter must
// replace the output on success and leave it untouched on failure, so tests can
// see which happened.
class ScholaEnvironmentTestDriver : public godot::RefCounted {
	GDCLASS(ScholaEnvironmentTestDriver, godot::RefCounted)

public:
	// "agents" maps each agent ID to its resolved agent_type.
	godot::Dictionary initialize(ScholaEnvironment *p_node) {
		if (p_node == nullptr || p_node->get_environment() == nullptr) {
			return missing_environment();
		}
		std::map<schola::AgentId, schola::InteractionDefinition> output;
		output["sentinel"].agent_type = "sentinel";
		const schola::Status status = p_node->get_environment()->initialize(output);
		if (status.is_ok()) {
			definitions = output;
		}
		godot::Dictionary result = response(status);
		godot::Dictionary agents;
		for (const auto &[id, definition] : output) {
			agents[to_godot(id)] = to_godot(definition.agent_type);
		}
		result["agents"] = agents;
		return result;
	}

	// p_settings may hold an int "seed" and an "options" Dictionary of Strings.
	// "states" maps each agent ID to its observation and info.
	godot::Dictionary reset(ScholaEnvironment *p_node, const godot::Dictionary &p_settings) {
		if (p_node == nullptr || p_node->get_environment() == nullptr) {
			return missing_environment();
		}
		schola::ResetSettings settings;
		if (p_settings.has("seed")) {
			const int64_t seed = p_settings["seed"];
			settings.seed = static_cast<int32_t>(seed);
		}
		const godot::Dictionary options = p_settings.get("options", godot::Dictionary());
		const godot::Array option_keys = options.keys();
		for (int32_t index = 0; index < option_keys.size(); ++index) {
			const godot::String key = option_keys[index];
			const godot::String value = options[option_keys[index]];
			settings.options[to_std(key)] = to_std(value);
		}

		std::map<schola::AgentId, schola::InitialAgentState> states;
		states["sentinel"].observation = schola::DiscretePoint{ -1 };
		const schola::Status status = p_node->get_environment()->reset(settings, states);
		godot::Dictionary result = response(status);
		godot::Dictionary output;
		for (const auto &[id, state] : states) {
			godot::Dictionary entry;
			entry["observation"] = schola::point_to_variant(state.observation);
			entry["info"] = to_dictionary(state.info);
			output[to_godot(id)] = entry;
		}
		result["states"] = output;
		return result;
	}

	// Converts each action with the agent's action space, as a trainer would.
	godot::Dictionary step(ScholaEnvironment *p_node, const godot::Dictionary &p_actions) {
		if (p_node == nullptr || p_node->get_environment() == nullptr) {
			return missing_environment();
		}
		std::map<schola::AgentId, schola::Point> actions;
		const godot::Array keys = p_actions.keys();
		for (int32_t index = 0; index < keys.size(); ++index) {
			const godot::String id = keys[index];
			const std::string key = to_std(id);
			const auto definition = definitions.find(key);
			if (definition == definitions.end()) {
				return response(schola::Status::error(schola::StatusCode::NOT_FOUND, "unknown test agent"));
			}
			schola::Point point;
			const schola::Status conversion = schola::variant_to_point(p_actions[id], definition->second.action_space, point);
			if (!conversion.is_ok()) {
				return response(conversion);
			}
			actions.emplace(key, std::move(point));
		}
		return run_step(p_node, actions);
	}

	// Passes each int to the adapter as a raw Discrete point, without the
	// conversion step() does, so unknown agents and out-of-range actions reach
	// the adapter's own checks.
	godot::Dictionary step_unchecked(ScholaEnvironment *p_node, const godot::Dictionary &p_actions) {
		if (p_node == nullptr || p_node->get_environment() == nullptr) {
			return missing_environment();
		}
		std::map<schola::AgentId, schola::Point> actions;
		const godot::Array keys = p_actions.keys();
		for (int32_t index = 0; index < keys.size(); ++index) {
			const godot::String id = keys[index];
			const int64_t value = p_actions[id];
			actions.emplace(to_std(id), schola::Point(schola::DiscretePoint{ static_cast<int32_t>(value) }));
		}
		return run_step(p_node, actions);
	}

	// "agents" names the node behind each returned agent, in the order returned.
	godot::Dictionary get_agents(ScholaEnvironment *p_node) {
		if (p_node == nullptr || p_node->get_environment() == nullptr) {
			return missing_environment();
		}
		std::vector<schola::Agent *> agents{ nullptr };
		const schola::Status status = p_node->get_environment()->get_agents(agents);

		std::map<const schola::Agent *, godot::String> names;
		const godot::TypedArray<ScholaAgent> nodes = p_node->get_agents();
		for (int32_t index = 0; index < nodes.size(); ++index) {
			godot::Object *object = nodes[index];
			if (ScholaAgent *agent = godot::Object::cast_to<ScholaAgent>(object)) {
				names[agent->get_agent()] = godot::String(agent->get_name());
			}
		}

		godot::Dictionary result = response(status);
		godot::Array output;
		for (const schola::Agent *agent : agents) {
			const auto name = names.find(agent);
			if (agent == nullptr) {
				output.push_back("sentinel");
			} else if (name == names.end()) {
				output.push_back("unknown");
			} else {
				output.push_back(name->second);
			}
		}
		result["agents"] = output;
		return result;
	}

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("initialize", "environment"), &ScholaEnvironmentTestDriver::initialize);
		godot::ClassDB::bind_method(godot::D_METHOD("reset", "environment", "settings"), &ScholaEnvironmentTestDriver::reset, DEFVAL(godot::Dictionary()));
		godot::ClassDB::bind_method(godot::D_METHOD("step", "environment", "actions"), &ScholaEnvironmentTestDriver::step);
		godot::ClassDB::bind_method(godot::D_METHOD("step_unchecked", "environment", "actions"), &ScholaEnvironmentTestDriver::step_unchecked);
		godot::ClassDB::bind_method(godot::D_METHOD("get_agents", "environment"), &ScholaEnvironmentTestDriver::get_agents);
	}

private:
	std::map<schola::AgentId, schola::InteractionDefinition> definitions;

	godot::Dictionary run_step(ScholaEnvironment *p_node, const std::map<schola::AgentId, schola::Point> &p_actions) {
		std::map<schola::AgentId, schola::AgentState> states;
		states["sentinel"].reward = 123.0f;
		const schola::Status status = p_node->get_environment()->step(p_actions, states);
		godot::Dictionary result = response(status);
		godot::Dictionary output;
		for (const auto &[id, state] : states) {
			godot::Dictionary entry;
			entry["observation"] = schola::point_to_variant(state.observation);
			entry["reward"] = state.reward;
			entry["terminated"] = state.terminated;
			entry["truncated"] = state.truncated;
			entry["info"] = to_dictionary(state.info);
			output[to_godot(id)] = entry;
		}
		result["states"] = output;
		return result;
	}

	static godot::String to_godot(const std::string &p_value) {
		return godot::String::utf8(p_value.c_str());
	}

	static std::string to_std(const godot::String &p_value) {
		return p_value.utf8().get_data();
	}

	static godot::Dictionary to_dictionary(const std::map<std::string, std::string> &p_values) {
		godot::Dictionary dictionary;
		for (const auto &[key, value] : p_values) {
			dictionary[to_godot(key)] = to_godot(value);
		}
		return dictionary;
	}

	static godot::Dictionary missing_environment() {
		return response(schola::Status::error(schola::StatusCode::FAILED_PRECONDITION, "Pass a valid ScholaEnvironment node that is inside the scene tree."));
	}

	static godot::Dictionary response(const schola::Status &p_status) {
		godot::Dictionary result;
		result["ok"] = p_status.is_ok();
		result["code"] = static_cast<int64_t>(p_status.get_code());
		result["message"] = to_godot(p_status.get_message());
		return result;
	}
};

void register_schola_environment_test_driver() {
	GDREGISTER_CLASS(ScholaEnvironmentTestDriver);
}
