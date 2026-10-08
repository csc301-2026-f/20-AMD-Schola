#pragma once

#include "core/spaces/space_kind.h"

#include <cstdint>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace schola {

class Point;

struct BoxPoint {
	std::vector<float> values;
};

struct DiscretePoint {
	int32_t value = 0;
};

struct MultiDiscretePoint {
	std::vector<int32_t> values;
};

struct MultiBinaryPoint {
	std::vector<uint8_t> values;
};

struct DictPoint {
	std::vector<std::pair<std::string, Point>> entries;
	Point *find(const std::string &p_key);
	const Point *find(const std::string &p_key) const;
};

class Point {
public:
	Point();
	Point(BoxPoint p_point);
	Point(DiscretePoint p_point);
	Point(MultiDiscretePoint p_point);
	Point(MultiBinaryPoint p_point);
	Point(DictPoint p_point);

	SpaceKind get_kind() const;
	template <typename T>
	T *get_if();
	template <typename T>
	const T *get_if() const;
	std::string to_string() const;

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

}
