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
