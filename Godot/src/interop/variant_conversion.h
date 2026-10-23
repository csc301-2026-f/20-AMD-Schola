// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include <godot_cpp/variant/variant.hpp>

namespace schola {
class Point;
class Space;
class Status;

// Converts a Godot value into a Point matching p_space
// Returns INVALID_ARGUMENT when the value has the wrong type, kind, or size
// US1 calls this for values returned by ScholaAgent::_observe()
Status variant_to_point(const godot::Variant &p_value, const Space &p_space, Point &r_point);

// Converts a Point into its Godot value representation
// US1 calls this before passing an action to ScholaAgent::_act()
godot::Variant point_to_variant(const Point &p_point);

// Parses a space dictionary such as {"kind": "discrete", "n": 4}
// Returns INVALID_ARGUMENT for a malformed dictionary and INVALID_DATA for an invalid definition
Status variant_to_space(const godot::Variant &p_value, Space &r_space);

// Produces the space dictionary used across the extension boundary
godot::Variant space_to_variant(const Space &p_space);

}
