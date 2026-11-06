// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/spaces/space_kind.h"

#include <cstdint>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace schola {

class Point;

// Box values in row-major order.
struct BoxPoint {
	std::vector<float> values;
};

// Selected index in [0, n).
struct DiscretePoint {
	int32_t value = 0;
};

// One selected index per dimension; values[i] is in [0, nvec[i]).
struct MultiDiscretePoint {
	std::vector<int32_t> values;
};

// One 0 or 1 value per dimension.
struct MultiBinaryPoint {
	std::vector<uint8_t> values;
};

// Entries follow the DictSpace's sorted key order. Protobuf maps are unordered, so converters walk the
// DictSpace, not the map.
struct DictPoint {
	std::vector<std::pair<std::string, Point>> entries;
	// Returns nullptr if p_key is absent. Invalidated when entries changes.
	Point *find(const std::string &p_key);
	const Point *find(const std::string &p_key) const;
};

// A value in a Space; check it with Space::validate(). Owns all its data and is safe to copy.
class Point {
public:
	// Constructs an empty Box point.
	Point();
	Point(BoxPoint p_point);
	Point(DiscretePoint p_point);
	Point(MultiDiscretePoint p_point);
	Point(MultiBinaryPoint p_point);
	Point(DictPoint p_point);

	SpaceKind get_kind() const;
	// Returns nullptr if the point holds a different kind.
	template <typename T>
	T *get_if();
	template <typename T>
	const T *get_if() const;
	std::string to_string() const;

	// Exact comparison, including Dict entry order.
	bool operator==(const Point &p_other) const;
	bool operator!=(const Point &p_other) const;

private:
	using Data = std::variant<BoxPoint, DiscretePoint, MultiDiscretePoint, MultiBinaryPoint, DictPoint>;
	Data data;
};

template <typename T>
T *Point::get_if() {
	return std::get_if<T>(&data);
}

template <typename T>
const T *Point::get_if() const {
	return std::get_if<T>(&data);
}

} // namespace schola
