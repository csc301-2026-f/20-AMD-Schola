// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"
#include "core/spaces/point.h"
#include "core/spaces/space_kind.h"

#include <cstdint>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace schola {

class Space;

// Returns the numpy name, such as "uint8", or "unknown".
const char *dtype_name(DType p_dtype);

// Returns true for integer and bool dtypes, whose Box bounds and values must be whole numbers.
bool is_whole_dtype(DType p_dtype);

// low and high hold product(shape) values in row-major order; infinity means unbounded. An empty
// protobuf shape becomes {low.size()}. Integer and bool dtypes need finite, whole, in-range bounds and
// whole values, because numpy truncates or garbles anything else.
struct BoxSpace {
	std::vector<float> low;
	std::vector<float> high;
	std::vector<int32_t> shape;
	DType dtype = DType::FLOAT32;
};

// A single choice in [0, n), where n is positive.
struct DiscreteSpace {
	int32_t n = 0;
};

// Independent choices; dimension i is in [0, nvec[i]). nvec is non-empty and every entry is positive.
struct MultiDiscreteSpace {
	std::vector<int32_t> nvec;
};

// n independent 0 or 1 values, where n is positive.
struct MultiBinarySpace {
	int32_t n = 0;
};

// Named subspaces, sorted by key to match gymnasium's Dict order and flattened layout.
struct DictSpace {
	std::vector<std::pair<std::string, Space>> entries;
	// Returns nullptr if p_key is absent. Invalidated when entries changes.
	const Space *find(const std::string &p_key) const;
};

// An observation or action space. Owns all its data and is safe to copy.
class Space {
public:
	// Constructs an empty Box space.
	Space();
	Space(BoxSpace p_space);
	Space(DiscreteSpace p_space);
	Space(MultiDiscreteSpace p_space);
	Space(MultiBinarySpace p_space);
	// Sorts entries by key.
	Space(DictSpace p_space);

	SpaceKind get_kind() const;
	// Returns nullptr if the space holds a different kind.
	template <typename T>
	const T *get_if() const;

	// Returns INVALID_DATA, naming the field and Dict key path, if the definition is malformed.
	Status check_definition() const;
	// Returns INVALID_ARGUMENT, naming the index and Dict key path, if p_point does not fit. Never changes
	// the point. Assumes check_definition() passed.
	Status validate(const Point &p_point) const;
	// Returns a valid point of zeros, with Box values clamped to their bounds.
	Point make_point() const;
	// Matches Unreal Schola: Discrete is n (one-hot), MultiDiscrete is sum(nvec), Dict sums its entries.
	int64_t get_flattened_size() const;
	std::string to_string() const;

	// Exact comparison. Dict entries are sorted, so declaration order does not matter.
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
