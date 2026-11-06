// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/variant/callable.hpp>

#include <vector>

namespace schola::configuration {

// Script metadata also works for non-tool scripts that do not run in the editor.
inline bool has_hook(const godot::Object *p_node, const godot::StringName &p_name) {
	godot::Ref<godot::Script> script = p_node->get_script();
	while (script.is_valid()) {
		if (script->has_script_method(p_name)) {
			return true;
		}
		script = script->get_base_script();
	}
	return false;
}

inline void disconnect_scripts(std::vector<godot::Ref<godot::Script>> &r_scripts, const godot::Callable &p_callback) {
	for (const godot::Ref<godot::Script> &script : r_scripts) {
		if (script->is_connected("changed", p_callback)) {
			script->disconnect("changed", p_callback);
		}
	}
	r_scripts.clear();
}

inline void watch_scripts(const godot::Object *p_node, std::vector<godot::Ref<godot::Script>> &r_scripts, const godot::Callable &p_callback) {
	disconnect_scripts(r_scripts, p_callback);
	godot::Ref<godot::Script> script = p_node->get_script();
	while (script.is_valid()) {
		if (!script->is_connected("changed", p_callback)) {
			script->connect("changed", p_callback);
		}
		r_scripts.push_back(script);
		script = script->get_base_script();
	}
}

} // namespace schola::configuration
