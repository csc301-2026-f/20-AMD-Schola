// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include <godot_cpp/variant/variant.hpp>

namespace schola {
class Point;
class Space;
class Status;

// Converts and validates a Godot value. Returns INVALID_ARGUMENT and leaves r_point unchanged on
// failure. Assumes p_space passed check_definition().
Status variant_to_point(const godot::Variant &p_value, const Space &p_space, Point &r_point);

// Converts a Point into a Godot value
godot::Variant point_to_variant(const Point &p_point);

} //namespace schola
