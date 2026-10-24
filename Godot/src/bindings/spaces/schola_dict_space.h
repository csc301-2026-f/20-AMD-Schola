// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/spaces/schola_space.h"

#include <godot_cpp/variant/dictionary.hpp>

// Inspector resource for a named collection of US2 spaces
class ScholaDictSpace : public ScholaSpace {
	GDCLASS(ScholaDictSpace, ScholaSpace)

public:
	// Maps each String key to one ScholaSpace resource
	void set_spaces(const godot::Dictionary &p_spaces);
	godot::Dictionary get_spaces() const;

	// A Dict that contains itself yields an empty Box entry where the cycle closes
	schola::Space to_space() const override;
	// Reports a non-String key, an entry without a ScholaSpace, or a Dict that contains itself
	godot::String get_resource_error(const godot::String &p_path) const override;

protected:
	static void _bind_methods();

private:
	godot::Dictionary spaces;
	// Set while this resource's entries are being walked, so a cycle stops instead of recursing forever
	mutable bool visiting = false;
};
