// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "core/environment/interaction_definition.h"
#include "core/policy/policy_state.h"
#include "core/spaces/space.h"
#include "inference/onnx_policy.h"
#include "inference/onnx_policy_state.h"
#include "test_fixtures_path.h"

#include <catch_amalgamated.hpp>

#include <cmath>
#include <cstdint>
#include <fstream>
#include <iterator>
#include <limits>
#include <memory>
#include <string>
#include <utility>
#include <vector>

using Catch::Matchers::ContainsSubstring;
using namespace schola;

namespace {

Status load(OnnxPolicy &r_policy, const std::string &p_name) {
	std::ifstream file(std::string(SCHOLA_TEST_FIXTURES_DIR) + "/" + p_name, std::ios::binary);
	REQUIRE(file.is_open());
	std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
	return r_policy.load_model(bytes.data(), bytes.size(), p_name);
}

Space box(int32_t p_size, float p_bound = 10.0f) {
	return Space(BoxSpace{ std::vector<float>(p_size, -p_bound), std::vector<float>(p_size, p_bound), { p_size } });
}

InteractionDefinition definition(Space p_observation, Space p_action) {
	InteractionDefinition result;
	result.observation_space = std::move(p_observation);
	result.action_space = std::move(p_action);
	return result;
}

struct Fixture {
	OnnxPolicy policy;
	std::unique_ptr<PolicyState> state;
	Point action;

	Fixture(const std::string &p_model, const InteractionDefinition &p_definition) {
		REQUIRE(load(policy, p_model).is_ok());
		Status status = policy.init(p_definition);
		INFO(status.get_message());
		REQUIRE(status.is_ok());
		REQUIRE(policy.create_initial_state(state).is_ok());
		action = p_definition.action_space.make_point();
	}

	Status think(const Point &p_observation) { return policy.think(p_observation, *state, action); }
};

std::vector<float> box_values(const Point &p_point) {
	return p_point.get_if<BoxPoint>()->values;
}

} // namespace

TEST_CASE("think runs a Box model", "[inference]") {
	Fixture fixture("box_scale.onnx", definition(box(3), box(3)));
	REQUIRE(fixture.policy.is_ready());
	REQUIRE(dynamic_cast<EmptyPolicyState *>(fixture.state.get()) != nullptr);

	REQUIRE(fixture.think(Point(BoxPoint{ { 1.0f, 2.0f, 3.0f } })).is_ok());
	REQUIRE(box_values(fixture.action) == std::vector<float>{ 2.0f, 4.0f, 6.0f });
}

TEST_CASE("integer ONNX inputs reject Box observations outside their numeric range", "[inference][integer-input]") {
	const int type = GENERATE(0, 1, 2, 3, 4, 5);
	const char *models[] = { "int8_box.onnx", "uint8_box.onnx", "int16_box.onnx", "uint16_box.onnx", "int32_box.onnx", "int64_box.onnx" };
	const int digits[] = { 7, 8, 15, 16, 31, 63 };
	const float upper = std::ldexp(1.0f, digits[type]);
	const bool is_unsigned = type == 1 || type == 3;
	const float lower = is_unsigned ? 0.0f : -upper;
	const float bad = GENERATE_COPY(upper, is_unsigned ? -1.0f : std::floor(std::nextafter(lower, -INFINITY)), INFINITY, -INFINITY, std::nanf(""));
	Fixture fixture(models[type], definition(box(3, INFINITY), box(3, INFINITY)));
	const Status status = fixture.think(Point(BoxPoint{ { 0.0f, bad, 1.0f } }));
	INFO(models[type]);
	INFO(bad);
	CHECK(status.get_code() == StatusCode::INVALID_ARGUMENT);
	CHECK_THAT(status.get_message(), ContainsSubstring("observation"));
	CHECK_THAT(status.get_message(), ContainsSubstring("index 1"));
	CHECK_THAT(status.get_message(), ContainsSubstring("integer tensor"));
	// A rejected call must leave the model usable for the next observation.
	REQUIRE(fixture.think(Point(BoxPoint{ { lower, 0.0f, std::floor(std::nextafter(upper, 0.0f)) } })).is_ok());
}

TEST_CASE("integer ONNX inputs preserve representable Box observations", "[inference][integer-input]") {
	const char *name = GENERATE("int8_box.onnx", "uint8_box.onnx", "int16_box.onnx", "uint16_box.onnx", "int32_box.onnx", "int64_box.onnx");
	Fixture fixture(name, definition(box(3, INFINITY), box(3, INFINITY)));
	REQUIRE(fixture.think(Point(BoxPoint{ { 0.0f, 1.0f, 42.0f } })).is_ok());
	CHECK(box_values(fixture.action) == std::vector<float>{ 0.0f, 1.0f, 42.0f });
}

TEST_CASE("integer ONNX inputs preserve safe fractional truncation", "[inference][integer-input]") {
	SECTION("signed values near both limits") {
		Fixture fixture("int8_box.onnx", definition(box(3, INFINITY), box(3, INFINITY)));
		REQUIRE(fixture.think(Point(BoxPoint{ { -128.5f, 127.5f, 1.75f } })).is_ok());
		CHECK(box_values(fixture.action) == std::vector<float>{ -128.0f, 127.0f, 1.0f });
	}
	SECTION("negative fractions that truncate to unsigned zero") {
		Fixture fixture("uint8_box.onnx", definition(box(3, INFINITY), box(3, INFINITY)));
		REQUIRE(fixture.think(Point(BoxPoint{ { -0.5f, 255.5f, 1.75f } })).is_ok());
		CHECK(box_values(fixture.action) == std::vector<float>{ 0.0f, 255.0f, 1.0f });
	}
}

TEST_CASE("think returns Discrete, MultiDiscrete, and MultiBinary actions", "[inference]") {
	SECTION("Discrete") {
		Fixture fixture("discrete.onnx", definition(box(4), Space(DiscreteSpace{ 4 })));
		REQUIRE(fixture.think(Point(BoxPoint{ { 0.0f, 5.0f, 1.0f, 2.0f } })).is_ok());
		REQUIRE(fixture.action.get_if<DiscretePoint>()->value == 1);
	}
	SECTION("MultiDiscrete") {
		Space space(MultiDiscreteSpace{ { 4, 4 } });
		Fixture fixture("multi_discrete.onnx", definition(space, space));
		REQUIRE(fixture.think(Point(MultiDiscretePoint{ { 3, 1 } })).is_ok());
		REQUIRE(fixture.action.get_if<MultiDiscretePoint>()->values == std::vector<int32_t>{ 3, 1 });
	}
	SECTION("MultiBinary") {
		Space space(MultiBinarySpace{ 3 });
		Fixture fixture("multi_binary.onnx", definition(space, space));
		REQUIRE(fixture.think(Point(MultiBinaryPoint{ { 1, 0, 1 } })).is_ok());
		REQUIRE(fixture.action.get_if<MultiBinaryPoint>()->values == std::vector<uint8_t>{ 1, 0, 1 });
	}
}

TEST_CASE("think matches Dict observations and actions by key", "[inference]") {
	SECTION("observation") {
		Space observation(DictSpace{ { { "b", Space(DiscreteSpace{ 5 }) }, { "a", box(2) } } });
		Fixture fixture("dict_obs.onnx", definition(observation, box(3)));
		DictPoint point{ { { "a", Point(BoxPoint{ { 1.0f, 2.0f } }) }, { "b", Point(DiscretePoint{ 4 }) } } };
		REQUIRE(fixture.think(Point(point)).is_ok());
		REQUIRE(box_values(fixture.action) == std::vector<float>{ 1.0f, 2.0f, 4.0f });
	}
	SECTION("action") {
		Space action(DictSpace{ { { "jump", Space(DiscreteSpace{ 2 }) }, { "move", box(2) } } });
		Fixture fixture("dict_action.onnx", definition(box(2), action));
		REQUIRE(fixture.think(Point(BoxPoint{ { 0.0f, 9.0f } })).is_ok());
		const DictPoint *dict = fixture.action.get_if<DictPoint>();
		REQUIRE(dict->entries[0].second.get_if<DiscretePoint>()->value == 1);
		REQUIRE(box_values(dict->entries[1].second) == std::vector<float>{ 0.0f, 9.0f });
	}
}

TEST_CASE("think rejects integer actions that do not fit int32", "[inference][regression]") {
	const bool discrete = GENERATE(true, false);
	const float value = GENERATE(2147483648.0f, 4294967296.0f, -2147483904.0f, -4294967296.0f);
	const int32_t size = discrete ? 1 : 2;
	const Space action = discrete ? Space(DiscreteSpace{ 4 }) : Space(MultiDiscreteSpace{ { 4, 4 } });
	Fixture fixture(discrete ? "int64_discrete.onnx" : "int64_multi_discrete.onnx", definition(box(size, 4294967296.0f), action));
	const Status status = fixture.think(Point(BoxPoint{ std::vector<float>(size, value) }));
	REQUIRE(status.get_code() == StatusCode::INVALID_DATA);
	REQUIRE_THAT(status.get_message(), ContainsSubstring("int32"));
}

TEST_CASE("think preserves representable integer actions", "[inference][regression]") {
	const bool discrete = GENERATE(true, false);
	const int32_t value = GENERATE(0, 2147483520, (-2147483647 - 1));
	const int32_t size = discrete ? 1 : 2;
	const Space action = discrete ? Space(DiscreteSpace{ 4 }) : Space(MultiDiscreteSpace{ { 4, 4 } });
	Fixture fixture(discrete ? "int64_discrete.onnx" : "int64_multi_discrete.onnx", definition(box(size, 4294967296.0f), action));
	REQUIRE(fixture.think(Point(BoxPoint{ std::vector<float>(size, static_cast<float>(value)) })).is_ok());
	if (discrete) {
		REQUIRE(fixture.action.get_if<DiscretePoint>()->value == value);
	} else {
		REQUIRE(fixture.action.get_if<MultiDiscretePoint>()->values == std::vector<int32_t>{ value, value });
	}
}

TEST_CASE("init rejects spaces that do not fit the model", "[inference]") {
	OnnxPolicy policy;
	REQUIRE(policy.init(definition(box(3), box(3))).get_code() == StatusCode::FAILED_PRECONDITION);
	REQUIRE(load(policy, "box_scale.onnx").is_ok());

	Status wrong_size = policy.init(definition(box(2), box(3)));
	REQUIRE(wrong_size.get_code() == StatusCode::INCOMPATIBLE);
	REQUIRE_THAT(wrong_size.get_message(), ContainsSubstring("input 'obs' has shape [?, 3], but the observation space needs [?, 2]"));

	Status wrong_kind = policy.init(definition(Space(DiscreteSpace{ 3 }), box(3)));
	REQUIRE(wrong_kind.get_code() == StatusCode::INCOMPATIBLE);
	REQUIRE_FALSE(policy.is_ready());

	REQUIRE(load(policy, "dict_obs.onnx").is_ok());
	Status missing_key = policy.init(definition(Space(DictSpace{ { { "a", box(2) } } }), box(3)));
	REQUIRE(missing_key.get_code() == StatusCode::INCOMPATIBLE);
	REQUIRE_THAT(missing_key.get_message(), ContainsSubstring("'b' has no matching observation"));
}

TEST_CASE("think keeps each state separate and leaves it unchanged on failure", "[inference]") {
	Fixture fixture("counter.onnx", definition(box(1), box(2)));
	const Point observation(BoxPoint{ { 0.0f } });

	for (float expected : { 0.0f, 1.0f, 2.0f }) {
		REQUIRE(fixture.think(observation).is_ok());
		REQUIRE(box_values(fixture.action) == std::vector<float>{ expected, expected });
	}

	std::unique_ptr<PolicyState> other;
	REQUIRE(fixture.policy.create_initial_state(other).is_ok());
	REQUIRE(fixture.policy.think(observation, *other, fixture.action).is_ok());
	REQUIRE(box_values(fixture.action) == std::vector<float>{ 0.0f, 0.0f });

	REQUIRE(fixture.think(Point(BoxPoint{ { 0.0f, 0.0f } })).get_code() == StatusCode::INVALID_ARGUMENT);
	REQUIRE(fixture.think(observation).is_ok());
	REQUIRE(box_values(fixture.action) == std::vector<float>{ 3.0f, 3.0f });

	fixture.state->reset();
	REQUIRE(fixture.think(observation).is_ok());
	REQUIRE(box_values(fixture.action) == std::vector<float>{ 0.0f, 0.0f });
}

TEST_CASE("think slides a state sequence of the declared length", "[inference]") {
	Fixture fixture("counter_seq_declared.onnx", definition(box(1), box(2)));
	REQUIRE(fixture.policy.get_sequence_warnings().empty());
	const Point observation(BoxPoint{ { 0.0f } });

	for (float expected : { 0.0f, 1.0f, 2.0f, 3.0f }) {
		REQUIRE(fixture.think(observation).is_ok());
		REQUIRE(box_values(fixture.action) == std::vector<float>{ expected, expected });
	}
	const OnnxPolicyState &state = static_cast<const OnnxPolicyState &>(*fixture.state);
	REQUIRE(state.to_string() == "OnnxPolicyState(state_in_h: 3x2)");
	REQUIRE(std::vector<float>(state.get_buffers()[0].values.begin(), state.get_buffers()[0].values.begin() + 6) == std::vector<float>{ 2, 2, 3, 3, 4, 4 });
}

TEST_CASE("a declared length runs on a fixed sequence dimension", "[inference]") {
	Fixture fixture("counter_seq_fixed.onnx", definition(box(1), box(2)));
	REQUIRE(fixture.state->to_string() == "OnnxPolicyState(state_in_h: 3x2)");
	REQUIRE(fixture.think(Point(BoxPoint{ { 0.0f } })).is_ok());
}

TEST_CASE("think accepts any state that fits the model", "[inference]") {
	Fixture first("counter.onnx", definition(box(1), box(2)));
	Fixture second("counter.onnx", definition(box(1), box(2)));
	const Point observation(BoxPoint{ { 0.0f } });

	REQUIRE(first.policy.think(observation, *second.state, first.action).is_ok());

	EmptyPolicyState empty;
	REQUIRE(first.policy.think(observation, empty, first.action).get_code() == StatusCode::INVALID_ARGUMENT);
}

TEST_CASE("think rejects a state created before the model was reloaded", "[inference]") {
	Fixture fixture("counter.onnx", definition(box(1), box(2)));
	REQUIRE(load(fixture.policy, "counter_seq_declared.onnx").is_ok());
	REQUIRE(fixture.policy.init(definition(box(1), box(2))).is_ok());

	Status status = fixture.think(Point(BoxPoint{ { 0.0f } }));
	REQUIRE(status.get_code() == StatusCode::INVALID_ARGUMENT);
	REQUIRE_THAT(status.get_message(), ContainsSubstring("create a new state after reloading"));
}

TEST_CASE("think clamps a Box action to its space", "[inference]") {
	Space action(BoxSpace{ { -1.0f, -1.0f, -1.0f }, { 1.0f, 2.0f, 1.0f }, { 3 } });
	Fixture fixture("box_scale.onnx", definition(box(3), action));

	REQUIRE(fixture.think(Point(BoxPoint{ { 3.0f, 0.25f, -3.0f } })).is_ok());
	REQUIRE(box_values(fixture.action) == std::vector<float>{ 1.0f, 0.5f, -1.0f });

	REQUIRE(fixture.think(Point(BoxPoint{ { std::nanf(""), 0.0f, 0.0f } })).is_ok());
	REQUIRE(std::isnan(box_values(fixture.action)[0]));
}

TEST_CASE("think passes on a Discrete action outside its space", "[inference]") {
	SECTION("Discrete") {
		Fixture fixture("discrete.onnx", definition(box(4), Space(DiscreteSpace{ 2 })));
		REQUIRE(fixture.think(Point(BoxPoint{ { 0.0f, 0.0f, 0.0f, 9.0f } })).is_ok());
		REQUIRE(fixture.action.get_if<DiscretePoint>()->value == 3);
	}
	SECTION("MultiDiscrete") {
		Space observation(MultiDiscreteSpace{ { 4, 4 } });
		Fixture fixture("multi_discrete.onnx", definition(observation, Space(MultiDiscreteSpace{ { 2, 2 } })));
		REQUIRE(fixture.think(Point(MultiDiscretePoint{ { 3, 1 } })).is_ok());
		REQUIRE(fixture.action.get_if<MultiDiscretePoint>()->values == std::vector<int32_t>{ 3, 1 });
	}
}

TEST_CASE("think rejects a Discrete observation outside its space", "[inference]") {
	SECTION("Discrete") {
		Space observation(DictSpace{ { { "b", Space(DiscreteSpace{ 5 }) }, { "a", box(2) } } });
		Fixture fixture("dict_obs.onnx", definition(observation, box(3)));
		DictPoint point{ { { "a", Point(BoxPoint{ { 1.0f, 2.0f } }) }, { "b", Point(DiscretePoint{ 5 }) } } };
		Status status = fixture.think(Point(point));
		REQUIRE(status.get_code() == StatusCode::INVALID_ARGUMENT);
		REQUIRE_THAT(status.get_message(), ContainsSubstring("observation 'b' value 5 is outside [0, 5)"));
	}
	SECTION("MultiDiscrete") {
		Space space(MultiDiscreteSpace{ { 4, 4 } });
		Fixture fixture("multi_discrete.onnx", definition(space, space));
		Status status = fixture.think(Point(MultiDiscretePoint{ { 3, 4 } }));
		REQUIRE(status.get_code() == StatusCode::INVALID_ARGUMENT);
		REQUIRE_THAT(status.get_message(), ContainsSubstring("observation value 4 is outside [0, 4)"));
	}
}

TEST_CASE("batched_think advances every entry's own state", "[inference]") {
	Fixture fixture("counter.onnx", definition(box(1), box(2)));
	std::unique_ptr<PolicyState> second;
	REQUIRE(fixture.policy.create_initial_state(second).is_ok());
	const Point observation(BoxPoint{ { 0.0f } });
	Point first_action = fixture.action;
	Point second_action = fixture.action;

	REQUIRE(fixture.think(observation).is_ok());
	REQUIRE(fixture.policy.batched_think({ &observation, &observation }, { fixture.state.get(), second.get() }, { &first_action, &second_action }).is_ok());

	REQUIRE(box_values(first_action) == std::vector<float>{ 1.0f, 1.0f });
	REQUIRE(box_values(second_action) == std::vector<float>{ 0.0f, 0.0f });
}
