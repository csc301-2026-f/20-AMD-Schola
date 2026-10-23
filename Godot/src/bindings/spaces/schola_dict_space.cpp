// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "bindings/spaces/schola_dict_space.h"

#include "core/spaces/space.h"

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

namespace {

godot::String at_path(const godot::String &p_path, const godot::String &p_message) {
	return p_path.is_empty() ? p_message : "at '" + p_path + "': " + p_message;
}

} // namespace

void ScholaDictSpace::set_spaces(const godot::Dictionary &p_spaces) {
	spaces = p_spaces;
	emit_changed();
}

godot::Dictionary ScholaDictSpace::get_spaces() const {
	return spaces;
}

schola::Space ScholaDictSpace::to_space() const {
	if (visiting) {
		return schola::Space();
	}
	visiting = true;
	schola::DictSpace dict;
	const godot::Array keys = spaces.keys();
	for (int64_t i = 0; i < keys.size(); ++i) {
		const godot::Ref<ScholaSpace> space = spaces[keys[i]];
		const godot::String key = keys[i];
		dict.entries.emplace_back(key.utf8().get_data(), space.is_valid() ? space->to_space() : schola::Space());
	}
	visiting = false;
	return schola::Space(std::move(dict));
}

godot::String ScholaDictSpace::get_resource_error(const godot::String &p_path) const {
	if (visiting) {
		return at_path(p_path, "Dict contains itself");
	}
	visiting = true;
	godot::String error;
	const godot::Array keys = spaces.keys();
	for (int64_t i = 0; i < keys.size() && error.is_empty(); ++i) {
		const godot::Variant key = keys[i];
		if (key.get_type() != godot::Variant::STRING && key.get_type() != godot::Variant::STRING_NAME) {
			error = at_path(p_path, "Dict key " + key.stringify() + " is not a String");
			continue;
		}
		const godot::String key_path = p_path.is_empty() ? godot::String(key) : p_path + godot::String(".") + godot::String(key);
		const godot::Ref<ScholaSpace> space = spaces[key];
		error = space.is_null() ? at_path(key_path, "no ScholaSpace is assigned") : space->get_resource_error(key_path);
	}
	visiting = false;
	return error;
}

void ScholaDictSpace::_bind_methods() {
	godot::ClassDB::bind_method(godot::D_METHOD("set_spaces", "spaces"), &ScholaDictSpace::set_spaces);
	godot::ClassDB::bind_method(godot::D_METHOD("get_spaces"), &ScholaDictSpace::get_spaces);

	ADD_PROPERTY(godot::PropertyInfo(godot::Variant::DICTIONARY, "spaces", godot::PROPERTY_HINT_DICTIONARY_TYPE, "String;ScholaSpace"), "set_spaces", "get_spaces");
}
