// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#pragma once

#include "core/common/status.h"

#include <string>

namespace schola {

class PolicyState {
public:
	virtual ~PolicyState() = default;

	virtual void reset() = 0;
	virtual Status copy_from(const PolicyState &p_other) = 0;
	virtual Status notify_state_update() { return Status::ok(); }
	virtual std::string to_string() const = 0;
};

class EmptyPolicyState final : public PolicyState {
public:
	void reset() override {}
	Status copy_from(const PolicyState &p_other) override {
		if (dynamic_cast<const EmptyPolicyState *>(&p_other) == nullptr) {
			return Status::error(StatusCode::INVALID_ARGUMENT, "EmptyPolicyState::copy_from: expected an EmptyPolicyState, got " + p_other.to_string());
		}
		return Status::ok();
	}
	std::string to_string() const override { return "EmptyPolicyState"; }
};

} // namespace schola
