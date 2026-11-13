// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace schola {
class Space;
class Status;

// Gymnasium-style Dictionary; infinite Box bounds become null for JSON
godot::Dictionary space_to_dictionary(const Space &p_space);

// Reverses space_to_dictionary(), so the training extension can rebuild the spaces
// ScholaTrainingHost reports. A null Box bound becomes infinity. Returns INVALID_DATA
// naming the bad field, or check_definition()'s error, and leaves r_space unchanged on
// failure.
Status dictionary_to_space(const godot::Variant &p_value, Space &r_space);

} // namespace schola
