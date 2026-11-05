// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "bindings/spaces/schola_space.h"

#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <vector>

// Inspector resource for a named collection of US2 spaces
class ScholaDictSpace : public ScholaSpace {
	GDCLASS(ScholaDictSpace, ScholaSpace)

public:
	~ScholaDictSpace() override;

	// Maps each String key to one ScholaSpace resource
	void set_spaces(const godot::Dictionary &p_spaces);
	godot::Dictionary get_spaces() const;

	// A cycle yields an empty Box where it closes
	schola::Space to_space() const override;
	// Reports non-String keys, unassigned entries, and cycles
	godot::String get_resource_error(const godot::String &p_path) const override;

protected:
	static void _bind_methods();

private:
	void disconnect_child_signals();
	void on_child_changed();

	godot::Dictionary spaces;
	std::vector<godot::ObjectID> connected_children;
	bool forwarding_change = false;
	// Set while this resource's entries are being walked, so a cycle stops instead of recursing forever
	mutable bool visiting = false;
};
