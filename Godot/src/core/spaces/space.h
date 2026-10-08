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

struct BoxSpace {
	std::vector<float> low;
	std::vector<float> high;
	std::vector<int32_t> shape;
	DType dtype = DType::FLOAT32;
};

struct DiscreteSpace {
	int32_t n = 0;
};

struct MultiDiscreteSpace {
	std::vector<int32_t> nvec;
};

struct MultiBinarySpace {
	int32_t n = 0;
};

struct DictSpace {
	std::vector<std::pair<std::string, Space>> entries;
	const Space *find(const std::string &p_key) const;
};

class Space {
public:
	Space();
	Space(BoxSpace p_space);
	Space(DiscreteSpace p_space);
	Space(MultiDiscreteSpace p_space);
	Space(MultiBinarySpace p_space);
	Space(DictSpace p_space);

	SpaceKind get_kind() const;
	template <typename T>
	const T *get_if() const;

	Status check_definition() const;
	Status validate(const Point &p_point) const;
	Point make_point() const;
	int64_t get_flattened_size() const;
	std::string to_string() const;

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

}
