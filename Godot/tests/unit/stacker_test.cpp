// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "core/adapters/stacker.h"

#include <catch_amalgamated.hpp>

#include <limits>

using namespace schola;

TEST_CASE("Box stackers reject oversized output before allocating bounds", "[adapters][regression]") {
	const Space input(BoxSpace{ { 0, 0 }, { 1, 1 }, { 2, 1 } });
	BoxStackerSettings settings;
	settings.stacker.stack_size = std::numeric_limits<int32_t>::max();
	settings.stack_dimension = 1;
	settings.add_new_dimension = GENERATE(true, false);
	BoxStacker stacker(settings);
	Space output(DiscreteSpace{ 3 });
	REQUIRE(stacker.configure(input, output).get_code() == StatusCode::INVALID_ARGUMENT);
	CHECK(output == Space(DiscreteSpace{ 3 }));
	Point result;
	CHECK(stacker.adapt(BoxPoint{ { 0, 0 } }, result).get_code() == StatusCode::FAILED_PRECONDITION);
}

TEST_CASE("Box history interleaves blocks along an inner axis", "[adapters]") {
	const Space input(BoxSpace{ { 0, 10 }, { 9, 19 }, { 2, 1 } });
	BoxStackerSettings settings;
	settings.stacker.stack_size = 2;
	settings.stack_dimension = 1;
	settings.add_new_dimension = GENERATE(true, false);
	BoxStacker stacker(settings);
	Space output;
	REQUIRE(stacker.configure(input, output).is_ok());
	const auto *box = output.get_if<BoxSpace>();
	REQUIRE(box);
	const std::vector<int32_t> expected_shape = settings.add_new_dimension
			? std::vector<int32_t>{ 2, 2, 1 }
			: std::vector<int32_t>{ 2, 2 };
	CHECK(box->shape == expected_shape);
	CHECK(box->low == std::vector<float>{ 0, 0, 10, 10 });
	Point result;
	REQUIRE(stacker.adapt(BoxPoint{ { 1, 11 } }, result).is_ok());
	CHECK(result == Point(BoxPoint{ { 1, 0, 11, 10 } }));
	REQUIRE(stacker.adapt(BoxPoint{ { 2, 12 } }, result).is_ok());
	REQUIRE(stacker.adapt(BoxPoint{ { 3, 13 } }, result).is_ok());
	CHECK(result == Point(BoxPoint{ { 3, 2, 13, 12 } }));
	CHECK(output.validate(result).is_ok());
}

TEST_CASE("Dict stackers isolate history and restore explicit defaults", "[adapters]") {
	const Space input(DictSpace{ { { "speed", Space(DiscreteSpace{ 10 }) } } });
	const Point fallback(DictPoint{ { { "speed", Point(DiscretePoint{ 4 }) } } });
	StackerSettings settings{ 2, fallback };
	DictStacker first(settings);
	DictStacker second(settings);
	Space output;
	REQUIRE(first.configure(input, output).is_ok());
	REQUIRE(second.configure(input, output).is_ok());
	const Point sample(DictPoint{ { { "speed", Point(DiscretePoint{ 7 }) } } });
	const Point expected(DictPoint{ { { "speed_0", Point(DiscretePoint{ 7 }) }, { "speed_1", Point(DiscretePoint{ 4 }) } } });
	Point result;
	REQUIRE(first.adapt(sample, result).is_ok());
	REQUIRE(first.adapt(sample, result).is_ok());
	REQUIRE(second.adapt(sample, result).is_ok());
	CHECK(result == expected);
	first.reset();
	REQUIRE(first.adapt(sample, result).is_ok());
	CHECK(result == expected);
	CHECK(output.validate(result).is_ok());
}

TEST_CASE("Stacker rejects bad inputs without consuming a history slot", "[adapters]") {
	DictStacker stacker(StackerSettings{ 2, {} });
	const Space input(DiscreteSpace{ 5 });
	Space output;
	Point result;
	REQUIRE(stacker.configure(input, output).is_ok());
	REQUIRE(stacker.adapt(DiscretePoint{ 1 }, result).is_ok());
	CHECK(stacker.adapt(DiscretePoint{ 5 }, result).get_code() == StatusCode::INVALID_ARGUMENT);
	REQUIRE(stacker.adapt(DiscretePoint{ 2 }, result).is_ok());
	CHECK(result == Point(DictPoint{ { { "Point_0", Point(DiscretePoint{ 2 }) }, { "Point_1", Point(DiscretePoint{ 1 }) } } }));
	CHECK_FALSE(stacker.configure(Space(DiscreteSpace{ 0 }), output).is_ok());
	CHECK(stacker.adapt(DiscretePoint{ 2 }, result).get_code() == StatusCode::FAILED_PRECONDITION);
}

TEST_CASE("Dict stack layout handles suffix ordering and reconfiguration", "[adapters]") {
	DictStacker stacker(StackerSettings{ 12, {} });
	const Space input(DictSpace{ { { "a", Space(DiscreteSpace{ 100 }) }, { "a_1", Space(DiscreteSpace{ 100 }) } } });
	Space output;
	REQUIRE(stacker.configure(input, output).is_ok());
	Point result;
	for (int32_t value = 1; value <= 14; ++value) {
		REQUIRE(stacker.adapt(DictPoint{ { { "a", Point(DiscretePoint{ value }) }, { "a_1", Point(DiscretePoint{ value + 20 }) } } }, result).is_ok());
	}
	REQUIRE(output.validate(result).is_ok());
	const auto *dict = result.get_if<DictPoint>();
	REQUIRE(dict);
	CHECK(*dict->find("a_0") == Point(DiscretePoint{ 14 }));
	CHECK(*dict->find("a_10") == Point(DiscretePoint{ 4 }));
	CHECK(*dict->find("a_1_11") == Point(DiscretePoint{ 23 }));

	REQUIRE(stacker.configure(Space(DiscreteSpace{ 100 }), output).is_ok());
	REQUIRE(stacker.adapt(DiscretePoint{ 8 }, result).is_ok());
	REQUIRE(output.validate(result).is_ok());
	dict = result.get_if<DictPoint>();
	REQUIRE(dict);
	CHECK(dict->entries.size() == 12);
	CHECK(dict->entries[2].first == "Point_10");
	CHECK(*dict->find("Point_0") == Point(DiscretePoint{ 8 }));
	CHECK(*dict->find("Point_11") == Point(DiscretePoint{ 0 }));

	REQUIRE(stacker.configure(Space(DictSpace{}), output).is_ok());
	REQUIRE(stacker.adapt(DictPoint{}, result).is_ok());
	CHECK(result == Point(DictPoint{}));
}

TEST_CASE("Box history recycling preserves rollover and aliased input", "[adapters]") {
	BoxStackerSettings settings;
	settings.stacker.stack_size = GENERATE(1, 3);
	BoxStacker stacker(settings);
	Space output;
	REQUIRE(stacker.configure(Space(BoxSpace{ { 0, 0 }, { 100, 100 }, { 2 } }), output).is_ok());
	Point result;
	for (int32_t i = 1; i <= 8; ++i) {
		result = Point(BoxPoint{ { static_cast<float>(i), static_cast<float>(i + 10) } });
		REQUIRE(stacker.adapt(result, result).is_ok());
		REQUIRE(output.validate(result).is_ok());
		const auto &values = result.get_if<BoxPoint>()->values;
		CHECK(values[0] == i);
		CHECK(values[1] == i + 10);
		if (settings.stacker.stack_size == 3 && i >= 3) {
			CHECK(values == std::vector<float>{ static_cast<float>(i), static_cast<float>(i + 10), static_cast<float>(i - 1), static_cast<float>(i + 9), static_cast<float>(i - 2), static_cast<float>(i + 8) });
		}
	}
	stacker.reset();
	REQUIRE(stacker.adapt(BoxPoint{ { 9, 19 } }, result).is_ok());
	if (settings.stacker.stack_size == 3) {
		CHECK(result == Point(BoxPoint{ { 9, 19, 0, 0, 0, 0 } }));
	} else {
		CHECK(result == Point(BoxPoint{ { 9, 19 } }));
	}
}

TEST_CASE("Dict stacker rejects out-of-order keys without updating history", "[adapters]") {
	DictStacker stacker(StackerSettings{ 2, {} });
	const Space input(DictSpace{ { { "a", Space(DiscreteSpace{ 10 }) }, { "b", Space(DiscreteSpace{ 10 }) } } });
	Space output;
	REQUIRE(stacker.configure(input, output).is_ok());

	Point result;
	const Point unsorted(DictPoint{ { { "b", Point(DiscretePoint{ 5 }) }, { "a", Point(DiscretePoint{ 1 }) } } });
	const Status status = stacker.adapt(unsorted, result);
	REQUIRE(status.get_code() == StatusCode::INVALID_ARGUMENT);
	CHECK(status.get_message().find("not sorted") != std::string::npos);
	CHECK(stacker.get_num_valid() == 0);

	const Point sorted(DictPoint{ { { "a", Point(DiscretePoint{ 1 }) }, { "b", Point(DiscretePoint{ 5 }) } } });
	REQUIRE(stacker.adapt(sorted, result).is_ok());
	CHECK(result == Point(DictPoint{ { { "a_0", Point(DiscretePoint{ 1 }) }, { "a_1", Point(DiscretePoint{ 0 }) }, { "b_0", Point(DiscretePoint{ 5 }) }, { "b_1", Point(DiscretePoint{ 0 }) } } }));
}
