// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

// Cannot be built or run until US3 generates protobuf bindings
#if __has_include("Spaces.pb.h")

#include "transport/grpc/space_conversion.h"

#include <catch_amalgamated.hpp>

#include <limits>

using namespace schola;

namespace {

constexpr float INF=std::numeric_limits<float>::infinity();

Space make_dict_space() {
	DictSpace dict;
	dict.entries.emplace_back("position", Space(BoxSpace{ { -INF,0.0f },{ INF,1.0f },{ 2 },DType::FLOAT32 }));
	dict.entries.emplace_back("mode", Space(DiscreteSpace{ 3 }));
	dict.entries.emplace_back("buttons", Space(MultiBinarySpace{ 2 }));
	return Space(std::move(dict));
}

Point make_dict_point() {
	DictPoint dict;
	dict.entries.emplace_back("buttons", Point(MultiBinaryPoint{ { 1,0 } }));
	dict.entries.emplace_back("mode", Point(DiscretePoint{ 2 }));
	dict.entries.emplace_back("position", Point(BoxPoint{ { -5.0f,0.5f } }));
	return Point(std::move(dict));
}

Space round_trip(const Space &p_space) {
	::Schola::Space message;
	space_to_proto(p_space, message);
	Space result;
	REQUIRE(proto_to_space(message, result).is_ok());
	return result;
}

Point round_trip(const Point &p_point, const Space &p_space) {
	::Schola::Point message;
	point_to_proto(p_point, p_space, message);
	Point result;
	REQUIRE(proto_to_point(message, p_space, result).is_ok());
	return result;
}

} // namespace

TEST_CASE("spaces round-trip through protobuf unchanged", "[spaces][transport]") {
	const Space spaces[]={
		Space(BoxSpace{ { -1.0f,-INF,0.0f,0.0f },{ 1.0f,INF,255.0f,255.0f },{ 2,2 },DType::UINT8 }),
		Space(DiscreteSpace{ 4 }),
		Space(MultiDiscreteSpace{ { 3,5,2 } }),
		Space(MultiBinarySpace{ 6 }),
		make_dict_space(),
	};
	for(const Space &space:spaces) {
		CAPTURE(space.to_string());
		CHECK(round_trip(space)==space);
	}
}

TEST_CASE("an unbounded Box side is left unset in protobuf", "[spaces][transport]") {
	::Schola::Space message;
	space_to_proto(Space(BoxSpace{ { -INF },{ 2.0f },{ 1 } }), message);
	REQUIRE(message.box_space().dimensions_size()==1);
	CHECK_FALSE(message.box_space().dimensions(0).has_low());
	CHECK(message.box_space().dimensions(0).high()==2.0f);
}

TEST_CASE("points round-trip through protobuf unchanged", "[spaces][transport]") {
	const Space box(BoxSpace{ { -1.0f,-1.0f },{ 1.0f,1.0f },{ 2 } });
	CHECK(round_trip(Point(BoxPoint{ { 0.25f,-1.0f } }), box)==Point(BoxPoint{ { 0.25f,-1.0f } }));
	CHECK(round_trip(Point(DiscretePoint{ 3 }), Space(DiscreteSpace{ 4 }))==Point(DiscretePoint{ 3 }));
	CHECK(round_trip(Point(MultiDiscretePoint{ { 2,0 } }), Space(MultiDiscreteSpace{ { 3,1 } }))==Point(MultiDiscretePoint{ { 2,0 } }));
	CHECK(round_trip(Point(MultiBinaryPoint{ { 1,0,1 } }), Space(MultiBinarySpace{ 3 }))==Point(MultiBinaryPoint{ { 1,0,1 } }));
	CHECK(round_trip(make_dict_point(), make_dict_space())==make_dict_point());
}

TEST_CASE("interaction definitions round-trip through protobuf unchanged", "[spaces][transport]") {
	InteractionDefinition definition;
	definition.observation_space=make_dict_space();
	definition.action_space=Space(DiscreteSpace{ 5 });
	definition.agent_type="runner";

	::Schola::AgentDefinition message;
	interaction_definition_to_proto(definition, message);
	InteractionDefinition result;
	REQUIRE(proto_to_interaction_definition(message, result).is_ok());
	CHECK(result.observation_space==definition.observation_space);
	CHECK(result.action_space==definition.action_space);
	CHECK(result.agent_type==definition.agent_type);
}

TEST_CASE("agent states round-trip through protobuf unchanged", "[spaces][transport]") {
	AgentState state;
	state.observation=make_dict_point();
	state.reward=-0.75f;
	state.terminated=true;
	state.truncated=false;
	state.info={ { "lap","2" },{ "checkpoint","north" } };

	::Schola::AgentState message;
	agent_state_to_proto(state, make_dict_space(), message);
	AgentState result;
	REQUIRE(proto_to_agent_state(message, make_dict_space(), result).is_ok());
	CHECK(result.observation==state.observation);
	CHECK(result.reward==state.reward);
	CHECK(result.terminated==state.terminated);
	CHECK(result.truncated==state.truncated);
	CHECK(result.info==state.info);
}

TEST_CASE("unsupported or invalid protobuf data is rejected", "[spaces][transport]") {
	SECTION("Text space") {
		::Schola::Space message;
		message.mutable_text_space()->set_max_length(8);
		Space space;
		CHECK(proto_to_space(message, space).get_code()==StatusCode::INCOMPATIBLE);
	}
	SECTION("unset space") {
		Space space;
		CHECK(proto_to_space(::Schola::Space(), space).get_code()==StatusCode::INVALID_DATA);
	}
	SECTION("malformed definition") {
		::Schola::Space message;
		message.mutable_discrete_space()->set_high(0);
		Space space;
		CHECK(proto_to_space(message, space).get_code()==StatusCode::INVALID_DATA);
	}
	SECTION("point outside its space") {
		::Schola::Point message;
		message.mutable_discrete_point()->set_value(4);
		Point point;
		const Status status=proto_to_point(message, Space(DiscreteSpace{ 4 }), point);
		CHECK(status.get_code()==StatusCode::INVALID_ARGUMENT);
	}
	SECTION("Dict point with a missing key") {
		::Schola::Point message;
		(*message.mutable_dict_point()->mutable_values())["mode"].mutable_discrete_point()->set_value(1);
		Point point;
		const Status status=proto_to_point(message, make_dict_space(), point);
		CHECK(status.get_code()==StatusCode::INVALID_ARGUMENT);
		CHECK(status.get_message().find("missing key")!=std::string::npos);
	}
}

#endif
