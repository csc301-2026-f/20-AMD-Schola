// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

// Test-only bridge so GdUnit4 exercises the actual C++ Environment interface.
// Compiled and registered only with integration_tests=yes.
#include "bindings/environment/schola_environment.h"
#include "core/environment/environment.h"
#include "interop/variant_conversion.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <map>

class ScholaEnvironmentTestDriver : public godot::RefCounted {
	GDCLASS(ScholaEnvironmentTestDriver, godot::RefCounted)

public:
	godot::Dictionary initialize(ScholaEnvironment *p_node) {
		return response(p_node->get_environment()->initialize(definitions));
	}

	godot::Dictionary reset(ScholaEnvironment *p_node) {
		std::map<schola::AgentId, schola::InitialAgentState> states;
		const schola::Status status = p_node->get_environment()->reset({}, states);
		godot::Dictionary result = response(status);
		result["state_count"] = static_cast<int64_t>(states.size());
		return result;
	}

	godot::Dictionary step(ScholaEnvironment *p_node, const godot::Dictionary &p_actions) {
		std::map<schola::AgentId, schola::Point> actions;
		const godot::Array keys = p_actions.keys();
		for (int32_t index = 0; index < keys.size(); ++index) {
			const godot::String id = keys[index];
			const std::string key = id.utf8().get_data();
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
		// Failed operations must leave the caller's existing output untouched.
		std::map<schola::AgentId, schola::AgentState> states;
		states["sentinel"].reward = 123.0f;
		const schola::Status status = p_node->get_environment()->step(actions, states);
		godot::Dictionary result = response(status);
		godot::Dictionary output;
		for (const auto &[id, state] : states) {
			godot::Dictionary entry;
			entry["observation"] = schola::point_to_variant(state.observation);
			entry["reward"] = state.reward;
			entry["terminated"] = state.terminated;
			entry["truncated"] = state.truncated;
			godot::Dictionary info;
			for (const auto &[key, value] : state.info) {
				info[godot::String::utf8(key.c_str())] = godot::String::utf8(value.c_str());
			}
			entry["info"] = info;
			output[godot::String::utf8(id.c_str())] = entry;
		}
		result["states"] = output;
		return result;
	}

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("initialize", "environment"), &ScholaEnvironmentTestDriver::initialize);
		godot::ClassDB::bind_method(godot::D_METHOD("reset", "environment"), &ScholaEnvironmentTestDriver::reset);
		godot::ClassDB::bind_method(godot::D_METHOD("step", "environment", "actions"), &ScholaEnvironmentTestDriver::step);
	}

private:
	std::map<schola::AgentId, schola::InteractionDefinition> definitions;

	static godot::Dictionary response(const schola::Status &p_status) {
		godot::Dictionary result;
		result["ok"] = p_status.is_ok();
		result["code"] = static_cast<int64_t>(p_status.get_code());
		result["message"] = godot::String::utf8(p_status.get_message().c_str());
		return result;
	}
};

void register_schola_environment_test_driver() {
	GDREGISTER_CLASS(ScholaEnvironmentTestDriver);
}
