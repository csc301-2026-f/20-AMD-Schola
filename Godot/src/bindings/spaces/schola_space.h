// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>

namespace schola {
class Space;
} // namespace schola

// Base Inspector resource for an observation or action space
class ScholaSpace : public godot::Resource {
	GDCLASS(ScholaSpace, godot::Resource)

public:
	// May be invalid; see get_definition_error()
	virtual schola::Space to_space() const = 0;

	// Returns why the resource cannot form a space; p_path is its Dict key path
	virtual godot::String get_resource_error(const godot::String &p_path) const;

	// Returns an empty string if p_value fits, otherwise why not
	godot::String get_validation_error(const godot::Variant &p_value) const;

	// Returns an empty string if the definition is valid
	godot::String get_definition_error() const;
	godot::Dictionary to_dictionary() const;
	int64_t get_flattened_size() const;
	godot::Variant make_default_value() const;
	godot::String describe() const;

protected:
	static void _bind_methods();

private:
	// Returns why the space is invalid, or an empty string
	godot::String build_space(schola::Space &r_space) const;
};
