// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/spaces/schola_space.h"

#include <godot_cpp/variant/dictionary.hpp>

// Inspector resource for a Dict space
class ScholaDictSpace : public ScholaSpace {
	GDCLASS(ScholaDictSpace, ScholaSpace)

public:
	// String keys to ScholaSpace resources
	void set_spaces(const godot::Dictionary &p_spaces);
	godot::Dictionary get_spaces() const;

	// A cycle yields an empty Box where it closes
	schola::Space to_space() const override;
	// Reports non-String keys, unassigned entries, and cycles
	godot::String get_resource_error(const godot::String &p_path) const override;

protected:
	static void _bind_methods();

private:
	godot::Dictionary spaces;
	// Stops cycles from recursing forever
	mutable bool visiting = false;
};
