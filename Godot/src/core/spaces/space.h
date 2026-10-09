// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/spaces/point.h"
#include "core/spaces/space_kind.h"
#include "core/spaces/space_validation_result.h"

#include <cstdint>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace schola {

class Space;

// Continuous values with per-element bounds. low and high hold one entry per element of shape,
// in row-major order.
struct BoxSpace {
	std::vector<float> low;
	std::vector<float> high;
	std::vector<int32_t> shape;
	DType dtype = DType::FLOAT32;
};

// A single choice in [0, n).
struct DiscreteSpace {
	int32_t n = 0;
};

// Independent choices; dimension i is in [0, nvec[i]).
struct MultiDiscreteSpace {
	std::vector<int32_t> nvec;
};

// n independent 0 or 1 values.
struct MultiBinarySpace {
	int32_t n = 0;
};

// Named subspaces. Entry order is part of the definition: it fixes the flattened layout and the
// order used when exchanging values with Python.
struct DictSpace {
	std::vector<std::pair<std::string, Space>> entries;
	// Returns a non-owning pointer to the subspace for p_key, or nullptr if the key is absent.
	// The pointer is invalidated when entries is modified.
	const Space *find(const std::string &p_key) const;
};

// An observation or action space definition.
class Space {
public:
	// Constructs an empty Box space.
	Space();
	Space(BoxSpace p_space);
	Space(DiscreteSpace p_space);
	Space(MultiDiscreteSpace p_space);
	Space(MultiBinarySpace p_space);
	Space(DictSpace p_space);

	SpaceKind get_kind() const;
	// Returns a non-owning pointer to the held definition, or nullptr if the space holds a different kind.
	template <typename T>
	const T *get_if() const;

	// Checks that the definition itself is well-formed, recursing into Dict entries.
	SpaceValidationResult check_definition() const;
	// Checks that p_point has this space's kind, size, bounds, and Dict keys. Assumes the definition
	// already passed check_definition().
	SpaceValidationResult validate(const Point &p_point) const;
	// Returns a point of this space's kind and size with every value set to zero.
	Point make_point() const;
	// Returns the flattened size, matching Unreal Schola: Box is the element count, Discrete is n
	// (one-hot), MultiDiscrete is the sum of nvec, MultiBinary is n, and Dict is the sum of its entries.
	int64_t get_flattened_size() const;
	std::string to_string() const;

	// Compares kind and definition exactly, including Dict entry order.
	bool operator==(const Space &p_other) const;
	bool operator!=(const Space &p_other) const;

private:
	using Data = std::variant<BoxSpace, DiscreteSpace, MultiDiscreteSpace, MultiBinarySpace, DictSpace>;
	Data data;
};

template <typename T>
const T *Space::get_if() const {
	return std::get_if<T>(&data);
}

} // namespace schola
