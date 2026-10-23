// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

// Cannot be built or run until US3 generates protobuf bindings
#if __has_include("Spaces.pb.h")

#include "transport/grpc/space_conversion.h"

#include <cmath>
#include <limits>
#include <string>
#include <utility>

namespace schola {

namespace {

std::string at_path(const std::string &p_path, const std::string &p_message) {
	if(p_path.empty())return p_message;
	return "at '"+p_path+"': "+p_message;
}

std::string join_path(const std::string &p_path, const std::string &p_key) {
	return p_path.empty()?p_key:p_path+"."+p_key;
}

Status error_at(StatusCode p_code, const std::string &p_path, const std::string &p_message) {
	return Status::error(p_code, at_path(p_path, p_message));
}

const Space &empty_space() {
	static const Space space;
	return space;
}

Status from_space_message(const ::Schola::Space &p_message, const std::string &p_path, Space &r_space) {
	switch(p_message.space_case()) {
		case ::Schola::Space::kBoxSpace: {
			const ::Schola::BoxSpace &message=p_message.box_space();
			if(!::Schola::DType_IsValid(message.dtype())) {
				return error_at(StatusCode::INCOMPATIBLE, p_path, "Box dtype "+std::to_string(static_cast<int>(message.dtype()))+" is not a known DType");
			}
			BoxSpace box;
			box.dtype=static_cast<DType>(message.dtype());
			box.shape.assign(message.shape_dimensions().begin(), message.shape_dimensions().end());
			if(box.shape.empty())box.shape.push_back(message.dimensions_size());
			for(const ::Schola::BoxSpace::BoxSpaceDimension &dimension:message.dimensions()) {
				box.low.push_back(dimension.has_low()?dimension.low():-std::numeric_limits<float>::infinity());
				box.high.push_back(dimension.has_high()?dimension.high():std::numeric_limits<float>::infinity());
			}
			r_space=Space(std::move(box));
			return Status::ok();
		}
		case ::Schola::Space::kDiscreteSpace:
			r_space=Space(DiscreteSpace{ p_message.discrete_space().high() });
			return Status::ok();
		case ::Schola::Space::kMultiDiscreteSpace: {
			const auto &high=p_message.multi_discrete_space().high();
			r_space=Space(MultiDiscreteSpace{ std::vector<int32_t>(high.begin(), high.end()) });
			return Status::ok();
		}
		case ::Schola::Space::kMultiBinarySpace:
			r_space=Space(MultiBinarySpace{ p_message.multi_binary_space().shape() });
			return Status::ok();
		case ::Schola::Space::kDictSpace: {
			DictSpace dict;
			for(const auto &entry:p_message.dict_space().spaces()) {
				Space space;
				Status status=from_space_message(entry.second, join_path(p_path, entry.first), space);
				if(!status.is_ok())return status;
				dict.entries.emplace_back(entry.first, std::move(space));
			}
			r_space=Space(std::move(dict));
			return Status::ok();
		}
		case ::Schola::Space::kTextSpace:return error_at(StatusCode::INCOMPATIBLE, p_path, "Text spaces are not supported");
		case ::Schola::Space::SPACE_NOT_SET:
			break;
	}
	return error_at(StatusCode::INVALID_DATA, p_path, "space has no definition");
}

Status from_point_message(const ::Schola::Point &p_message, const Space &p_space, const std::string &p_path, Point &r_point) {
	switch(p_message.point_case()) {
		case ::Schola::Point::kBoxPoint: {
			const auto &values=p_message.box_point().values();
			r_point=Point(BoxPoint{ std::vector<float>(values.begin(), values.end()) });
			return Status::ok();
		}
		case ::Schola::Point::kDiscretePoint:
			r_point=Point(DiscretePoint{ p_message.discrete_point().value() });
			return Status::ok();
		case ::Schola::Point::kMultiDiscretePoint: {
			const auto &values=p_message.multi_discrete_point().values();
			r_point=Point(MultiDiscretePoint{ std::vector<int32_t>(values.begin(), values.end()) });
			return Status::ok();
		}
		case ::Schola::Point::kMultiBinaryPoint: {
			const auto &values=p_message.multi_binary_point().values();
			r_point=Point(MultiBinaryPoint{ std::vector<uint8_t>(values.begin(), values.end()) });
			return Status::ok();
		}
		case ::Schola::Point::kDictPoint: {
			const DictSpace *dict=p_space.get_if<DictSpace>();
			if(dict==nullptr) {
				return error_at(StatusCode::INVALID_ARGUMENT, p_path, "expected a point for "+p_space.to_string()+" but got a Dict point");
			}
			const auto &values=p_message.dict_point().values();
			for(const auto &entry:values) {
				if(dict->find(entry.first)==nullptr) {
					return error_at(StatusCode::INVALID_ARGUMENT, p_path, "Dict point has unexpected key '"+entry.first+"'");
				}
			}
			DictPoint point;
			for(const auto &entry:dict->entries) {
				const auto found=values.find(entry.first);
				if(found==values.end()) {
					return error_at(StatusCode::INVALID_ARGUMENT, p_path, "Dict point is missing key '"+entry.first+"'");
				}
				Point entry_point;
				Status status=from_point_message(found->second, entry.second, join_path(p_path, entry.first), entry_point);
				if(!status.is_ok())return status;
				point.entries.emplace_back(entry.first, std::move(entry_point));
			}
			r_point=Point(std::move(point));
			return Status::ok();
		}
		case ::Schola::Point::kTextPoint:return error_at(StatusCode::INCOMPATIBLE, p_path, "Text points are not supported");
		case ::Schola::Point::POINT_NOT_SET:
			break;
	}
	return error_at(StatusCode::INVALID_ARGUMENT, p_path, "point has no value");
}

}

void space_to_proto(const Space &p_space, ::Schola::Space &r_message) {
	r_message.Clear();
	if(const BoxSpace *box=p_space.get_if<BoxSpace>()) {
		::Schola::BoxSpace *message=r_message.mutable_box_space();
		for(size_t i=0; i<box->low.size(); ++i) {
			::Schola::BoxSpace::BoxSpaceDimension *dimension=message->add_dimensions();
			if(!std::isinf(box->low[i]))dimension->set_low(box->low[i]);
			if(i<box->high.size()&&!std::isinf(box->high[i]))dimension->set_high(box->high[i]);
		}
		for(int32_t dimension:box->shape)message->add_shape_dimensions(dimension);
		message->set_dtype(static_cast<::Schola::DType>(box->dtype));
	} else if(const DiscreteSpace *discrete=p_space.get_if<DiscreteSpace>()) {
		r_message.mutable_discrete_space()->set_high(discrete->n);
	} else if(const MultiDiscreteSpace *multi_discrete=p_space.get_if<MultiDiscreteSpace>()) {
		::Schola::MultiDiscreteSpace *message=r_message.mutable_multi_discrete_space();
		for(int32_t n:multi_discrete->nvec)message->add_high(n);
	} else if(const MultiBinarySpace *multi_binary=p_space.get_if<MultiBinarySpace>()) {
		r_message.mutable_multi_binary_space()->set_shape(multi_binary->n);
	} else {
		auto *spaces=r_message.mutable_dict_space()->mutable_spaces();
		for(const auto &entry:p_space.get_if<DictSpace>()->entries) {
			space_to_proto(entry.second, (*spaces)[entry.first]);
		}
	}
}

Status proto_to_space(const ::Schola::Space &p_message, Space &r_space) {
	Space space;
	Status status=from_space_message(p_message, {}, space);
	if(!status.is_ok())return status;
	status=space.check_definition();
	if(status.is_ok())r_space=std::move(space);
	return status;
}

void point_to_proto(const Point &p_point, const Space &p_space, ::Schola::Point &r_message) {
	r_message.Clear();
	if(const BoxPoint *box=p_point.get_if<BoxPoint>()) {
		::Schola::BoxPoint *message=r_message.mutable_box_point();
		for(float value:box->values)message->add_values(value);
		if(const BoxSpace *space=p_space.get_if<BoxSpace>()) {
			for(int32_t dimension:space->shape)message->add_shape(dimension);
			message->set_dtype(static_cast<::Schola::DType>(space->dtype));
		} else {
			message->add_shape(static_cast<int32_t>(box->values.size()));
		}
	} else if(const DiscretePoint *discrete=p_point.get_if<DiscretePoint>()) {
		r_message.mutable_discrete_point()->set_value(discrete->value);
	} else if(const MultiDiscretePoint *multi_discrete=p_point.get_if<MultiDiscretePoint>()) {
		::Schola::MultiDiscretePoint *message=r_message.mutable_multi_discrete_point();
		for(int32_t value:multi_discrete->values)message->add_values(value);
	} else if(const MultiBinaryPoint *multi_binary=p_point.get_if<MultiBinaryPoint>()) {
		::Schola::MultiBinaryPoint *message=r_message.mutable_multi_binary_point();
		for(uint8_t value:multi_binary->values)message->add_values(value!=0);
	} else {
		const DictSpace *dict=p_space.get_if<DictSpace>();
		auto *values=r_message.mutable_dict_point()->mutable_values();
		for(const auto &entry:p_point.get_if<DictPoint>()->entries) {
			const Space *space=dict!=nullptr?dict->find(entry.first):nullptr;
			point_to_proto(entry.second, space!=nullptr?*space:empty_space(), (*values)[entry.first]);
		}
	}
}

Status proto_to_point(const ::Schola::Point &p_message, const Space &p_space, Point &r_point) {
	Point point;
	Status status=from_point_message(p_message, p_space, {}, point);
	if(!status.is_ok())return status;
	status=p_space.validate(point);
	if(status.is_ok())r_point=std::move(point);
	return status;
}

void interaction_definition_to_proto(const InteractionDefinition &p_definition, ::Schola::AgentDefinition &r_message) {
	space_to_proto(p_definition.observation_space, *r_message.mutable_obs_space());
	space_to_proto(p_definition.action_space, *r_message.mutable_action_space());
	r_message.set_agent_type(p_definition.agent_type);
}

Status proto_to_interaction_definition(const ::Schola::AgentDefinition &p_message, InteractionDefinition &r_definition) {
	InteractionDefinition definition;
	Status status=proto_to_space(p_message.obs_space(), definition.observation_space);
	if(!status.is_ok()) {
		return Status::error(status.get_code(), "observation space: "+status.get_message());
	}
	status=proto_to_space(p_message.action_space(), definition.action_space);
	if(!status.is_ok()) {
		return Status::error(status.get_code(), "action space: "+status.get_message());
	}
	definition.agent_type=p_message.agent_type();
	r_definition=std::move(definition);
	return Status::ok();
}

void agent_state_to_proto(const AgentState &p_state, const Space &p_observation_space, ::Schola::AgentState &r_message) {
	point_to_proto(p_state.observation, p_observation_space, *r_message.mutable_observations());
	r_message.set_reward(p_state.reward);
	r_message.set_terminated(p_state.terminated);
	r_message.set_truncated(p_state.truncated);
	r_message.mutable_info()->clear();
	for(const auto &entry:p_state.info)(*r_message.mutable_info())[entry.first]=entry.second;
}

Status proto_to_agent_state(const ::Schola::AgentState &p_message, const Space &p_observation_space, AgentState &r_state) {
	AgentState state;
	Status status=proto_to_point(p_message.observations(), p_observation_space, state.observation);
	if(!status.is_ok()) {
		return Status::error(status.get_code(), "observation: "+status.get_message());
	}
	state.reward=p_message.reward();
	state.terminated=p_message.terminated();
	state.truncated=p_message.truncated();
	state.info.insert(p_message.info().begin(), p_message.info().end());
	r_state=std::move(state);
	return Status::ok();
}

}

#endif
