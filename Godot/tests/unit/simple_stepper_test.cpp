// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "core/stepper/simple_stepper.h"
#include "support/test_agent.h"
#include "support/test_policy.h"

#include <catch_amalgamated.hpp>

#include <cstdint>
#include <functional>
#include <vector>

using Catch::Matchers::ContainsSubstring;
using schola::BoxPoint;
using schola::BoxSpace;
using schola::InteractionDefinition;
using schola::Point;
using schola::SimpleStepper;
using schola::Space;
using schola::Status;
using schola::StatusCode;
using schola::testing::CounterState;
using schola::testing::FakeAgent;
using schola::testing::FakePolicy;

namespace {

class CallbackAgent : public schola::Agent {
public:
	FakeAgent agent;
	std::function<void()> on_observe;
	std::function<void()> on_act;

	Status define(InteractionDefinition &r_definition) override { return agent.define(r_definition); }
	Status observe(Point &r_observation) override {
		Status status = agent.observe(r_observation);
		if (on_observe) {
			on_observe();
		}
		return status;
	}
	Status act(const Point &p_action) override {
		Status status = agent.act(p_action);
		if (on_act) {
			on_act();
		}
		return status;
	}
};

InteractionDefinition box_definition(int32_t p_size) {
	InteractionDefinition definition;
	definition.observation_space = Space(BoxSpace{ std::vector<float>(p_size, -1.0f), std::vector<float>(p_size, 1.0f), { p_size } });
	definition.action_space = Space(BoxSpace{ { -1.0f }, { 1.0f }, { 1 } });
	return definition;
}

FakeAgent make_agent(float p_observation) {
	FakeAgent agent;
	agent.definition = box_definition(1);
	agent.observation = Point(BoxPoint{ { p_observation } });
	return agent;
}

FakePolicy make_policy() {
	FakePolicy policy;
	policy.stateful = true;
	policy.action = Point(BoxPoint{ { 0.5f } });
	return policy;
}

float box_value(const Point &p_point) {
	return p_point.get_if<BoxPoint>()->values.at(0);
}

int32_t count_at(const SimpleStepper &p_stepper, int32_t p_index) {
	return static_cast<const CounterState *>(p_stepper.get_state(p_index))->count;
}

void step_times(SimpleStepper &p_stepper, int p_times) {
	for (int i = 0; i < p_times; ++i) {
		REQUIRE(p_stepper.step().is_ok());
	}
}

} // namespace

TEST_CASE("step passes each observation to the policy and each action to its agent", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());

	REQUIRE(stepper.step().is_ok());

	REQUIRE(policy.observations.size() == 2);
	REQUIRE(box_value(policy.observations[0]) == 1.0f);
	REQUIRE(box_value(policy.observations[1]) == 2.0f);
	REQUIRE(first.actions.size() == 1);
	REQUIRE(second.actions.size() == 1);
	REQUIRE(box_value(first.actions[0]) == 0.5f);
}

TEST_CASE("each entry keeps its own state", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());

	step_times(stepper, 3);

	REQUIRE(count_at(stepper, 0) == 3);
	REQUIRE(count_at(stepper, 1) == 3);
	REQUIRE(stepper.get_state(0) != stepper.get_state(1));
}

TEST_CASE("adding an agent that is already in the stepper is rejected", "[stepper]") {
	FakeAgent agent = make_agent(1.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &agent }, &policy).is_ok());
	step_times(stepper, 2);

	int32_t index = -1;
	Status status = stepper.add_agent(&agent, index);
	REQUIRE(status.get_code() == StatusCode::INVALID_ARGUMENT);
	REQUIRE_THAT(status.get_message(), ContainsSubstring("already in this stepper"));
	REQUIRE(stepper.get_agent_count() == 1);
	step_times(stepper, 1);

	REQUIRE(count_at(stepper, 0) == 3);
	REQUIRE(agent.actions.size() == 3);
}

TEST_CASE("init rejects an agent listed twice", "[stepper]") {
	FakeAgent agent = make_agent(1.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;

	REQUIRE(stepper.init({ &agent, &agent }, &policy).get_code() == StatusCode::INVALID_ARGUMENT);
	REQUIRE(stepper.get_agent_count() == 0);
}

TEST_CASE("removing an entry shifts later entries with their states", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first }, &policy).is_ok());
	step_times(stepper, 2);
	int32_t index = -1;
	REQUIRE(stepper.add_agent(&second, index).is_ok());
	step_times(stepper, 1);

	REQUIRE(stepper.remove_agent_at(0).is_ok());

	REQUIRE(stepper.get_agent_count() == 1);
	REQUIRE(stepper.get_agent(0) == &second);
	REQUIRE(count_at(stepper, 0) == 1);
}

TEST_CASE("remove_agent removes that agent's entry", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());

	REQUIRE(stepper.remove_agent(&first) == 1);
	REQUIRE(stepper.get_agent_count() == 1);
	REQUIRE(stepper.get_agent(0) == &second);
	REQUIRE(stepper.remove_agent(&first) == 0);
	REQUIRE(stepper.find_agent(&first) == -1);
}

TEST_CASE("observe receives a point shaped like the current observation space", "[stepper]") {
	FakeAgent small = make_agent(1.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &small }, &policy).is_ok());
	step_times(stepper, 1);
	REQUIRE(small.received_observations.back().get_if<BoxPoint>()->values.size() == 1);

	REQUIRE(stepper.remove_agent(&small) == 1);
	FakeAgent large = make_agent(1.0f);
	large.definition = box_definition(3);
	int32_t index = -1;
	REQUIRE(stepper.add_agent(&large, index).is_ok());
	step_times(stepper, 1);

	REQUIRE(large.received_observations.back().get_if<BoxPoint>()->values.size() == 3);
}

TEST_CASE("reset_state resets one entry and reset_states resets all", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());
	step_times(stepper, 3);

	REQUIRE(stepper.reset_state(1).is_ok());
	REQUIRE(count_at(stepper, 0) == 3);
	REQUIRE(count_at(stepper, 1) == 0);

	stepper.reset_states();
	REQUIRE(count_at(stepper, 0) == 0);
}

TEST_CASE("invalid indices return NOT_FOUND or nullptr", "[stepper]") {
	FakeAgent agent = make_agent(1.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &agent }, &policy).is_ok());

	REQUIRE(stepper.remove_agent_at(5).get_code() == StatusCode::NOT_FOUND);
	REQUIRE(stepper.reset_state(-1).get_code() == StatusCode::NOT_FOUND);
	REQUIRE(stepper.get_agent(1) == nullptr);
	REQUIRE(stepper.get_state(1) == nullptr);
}

TEST_CASE("resetting inference state clears the previous episode observation fallback", "[stepper][regression]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(0.5f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());
	REQUIRE(stepper.step().is_ok());
	const bool reset_all = GENERATE(true, false);
	if (reset_all) {
		stepper.reset_states();
	} else {
		REQUIRE(stepper.reset_state(0).is_ok());
	}
	first.observe_result = Status::error(StatusCode::RUNTIME_FAILURE, "sensor unavailable after reset");
	second.observe_result = first.observe_result;
	REQUIRE(stepper.step().get_code() == StatusCode::RUNTIME_FAILURE);
	REQUIRE(policy.observations.size() == 4);
	CHECK(box_value(policy.observations[2]) == 0.0f);
	CHECK(box_value(policy.observations[3]) == (reset_all ? 0.0f : 0.5f));
}

TEST_CASE("add_agent rejects bad input", "[stepper]") {
	FakeAgent agent = make_agent(1.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	int32_t index = -1;

	SECTION("before init") {
		REQUIRE(stepper.add_agent(&agent, index).get_code() == StatusCode::FAILED_PRECONDITION);
	}
	SECTION("a null agent") {
		REQUIRE(stepper.init({}, &policy).is_ok());
		REQUIRE(stepper.add_agent(nullptr, index).get_code() == StatusCode::INVALID_ARGUMENT);
	}
	SECTION("different spaces") {
		FakeAgent other = make_agent(1.0f);
		other.definition = box_definition(2);
		REQUIRE(stepper.init({ &agent }, &policy).is_ok());
		REQUIRE(stepper.add_agent(&other, index).get_code() == StatusCode::INCOMPATIBLE);
		REQUIRE(stepper.get_agent_count() == 1);
	}
	SECTION("define fails") {
		agent.define_result = Status::error(StatusCode::INVALID_DATA, "bad space");
		REQUIRE(stepper.init({}, &policy).is_ok());
		Status status = stepper.add_agent(&agent, index);
		REQUIRE(status.get_code() == StatusCode::INVALID_DATA);
		REQUIRE_THAT(status.get_message(), ContainsSubstring("bad space"));
	}
}

TEST_CASE("init leaves no entries when one agent fails", "[stepper]") {
	FakeAgent good = make_agent(1.0f);
	FakeAgent bad = make_agent(1.0f);
	bad.define_result = Status::error(StatusCode::INVALID_DATA, "bad space");
	FakePolicy policy = make_policy();
	SimpleStepper stepper;

	REQUIRE_FALSE(stepper.init({ &good, &bad }, &policy).is_ok());
	REQUIRE(stepper.get_agent_count() == 0);
}

TEST_CASE("an observe failure reuses the last observation and every agent still acts", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());
	REQUIRE(stepper.step().is_ok());

	second.observation = Point(BoxPoint{ { 9.0f } });
	second.observe_result = Status::error(StatusCode::RUNTIME_FAILURE, "sensor broke");
	Status status = stepper.step();

	REQUIRE(status.get_code() == StatusCode::RUNTIME_FAILURE);
	REQUIRE_THAT(status.get_message(), ContainsSubstring("agent 1: observe: sensor broke"));
	REQUIRE(policy.observations.size() == 4);
	REQUIRE(box_value(policy.observations[3]) == 2.0f);
	REQUIRE(first.actions.size() == 2);
	REQUIRE(second.actions.size() == 2);
	REQUIRE(count_at(stepper, 1) == 2);
}

TEST_CASE("removing an agent preserves the remaining agents cached observations", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());
	REQUIRE(stepper.step().is_ok());

	SECTION("remove by index") {
		REQUIRE(stepper.remove_agent_at(0).is_ok());
	}
	SECTION("remove by pointer") {
		REQUIRE(stepper.remove_agent(&first) == 1);
	}

	second.observe_result = Status::error(StatusCode::RUNTIME_FAILURE, "sensor broke");
	REQUIRE(stepper.step().get_code() == StatusCode::RUNTIME_FAILURE);
	REQUIRE(policy.observations.size() == 3);
	REQUIRE(box_value(policy.observations.back()) == 2.0f);
	REQUIRE(second.actions.size() == 2);
}

TEST_CASE("a think failure means no agent acts", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	policy.fail_at_call = 1;
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());

	Status status = stepper.step();

	REQUIRE_THAT(status.get_message(), ContainsSubstring("entry 1"));
	REQUIRE(first.actions.empty());
	REQUIRE(second.actions.empty());
}

TEST_CASE("an act failure still lets the other agents act", "[stepper]") {
	FakeAgent first = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	first.act_result = Status::error(StatusCode::RUNTIME_FAILURE, "no _act");
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());

	Status status = stepper.step();

	REQUIRE_THAT(status.get_message(), ContainsSubstring("agent 0: act: no _act"));
	REQUIRE(second.actions.size() == 1);
}

TEST_CASE("stepping with no agents succeeds and does nothing", "[stepper]") {
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({}, &policy).is_ok());
	REQUIRE(stepper.step().is_ok());
	REQUIRE(policy.observations.empty());
}

TEST_CASE("removing an agent while acting interrupts the step instead of silently skipping an agent", "[stepper][mutation]") {
	CallbackAgent first;
	first.agent = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());
	first.on_act = [&] { CHECK(stepper.remove_agent(&first) == 1); };

	const Status status = stepper.step();

	CHECK(status.get_code() == StatusCode::FAILED_PRECONDITION);
	CHECK_THAT(status.get_message(), ContainsSubstring("while acting"));
	REQUIRE(stepper.get_agent_count() == 1);
	CHECK(stepper.get_agent(0) == &second);
	REQUIRE(stepper.step().is_ok());
	CHECK(second.actions.size() == 1);
}

TEST_CASE("replacement during observation cannot pair an observation with another agent", "[stepper][mutation]") {
	CallbackAgent first;
	first.agent = make_agent(1.0f);
	FakeAgent second = make_agent(2.0f);
	FakeAgent replacement = make_agent(3.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &first, &second }, &policy).is_ok());
	first.on_observe = [&] {
		CHECK(stepper.remove_agent(&first) == 1);
		int32_t index = -1;
		CHECK(stepper.add_agent(&replacement, index).get_code() == StatusCode::FAILED_PRECONDITION);
	};

	const Status status = stepper.step();

	CHECK(status.get_code() == StatusCode::FAILED_PRECONDITION);
	CHECK(policy.observations.empty());
	CHECK(second.actions.empty());
	CHECK(replacement.actions.empty());
	int32_t index = -1;
	REQUIRE(stepper.add_agent(&replacement, index).is_ok());
	REQUIRE(stepper.step().is_ok());
	REQUIRE(policy.observations.size() == 2);
	CHECK(box_value(policy.observations[0]) == 2.0f);
	CHECK(box_value(policy.observations[1]) == 3.0f);
}

TEST_CASE("removing the last agent while observing interrupts safely", "[stepper][mutation]") {
	CallbackAgent agent;
	agent.agent = make_agent(1.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &agent }, &policy).is_ok());
	agent.on_observe = [&] { REQUIRE(stepper.remove_agent_at(0).is_ok()); };

	CHECK(stepper.step().get_code() == StatusCode::FAILED_PRECONDITION);
	CHECK(stepper.get_agent_count() == 0);
	CHECK(policy.observations.empty());
	CHECK(stepper.step().is_ok());
}

TEST_CASE("callbacks cannot restart or reenter an active step", "[stepper][mutation]") {
	CallbackAgent agent;
	agent.agent = make_agent(1.0f);
	FakePolicy policy = make_policy();
	SimpleStepper stepper;
	REQUIRE(stepper.init({ &agent }, &policy).is_ok());
	agent.on_observe = [&] {
		CHECK(stepper.init({}, &policy).get_code() == StatusCode::FAILED_PRECONDITION);
		CHECK(stepper.step().get_code() == StatusCode::FAILED_PRECONDITION);
	};

	REQUIRE(stepper.step().is_ok());
	CHECK(agent.agent.actions.size() == 1);
}
