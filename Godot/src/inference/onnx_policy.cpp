// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "inference/onnx_policy.h"

#include <onnxruntime_c_api.h>

#include <string>
#include <utility>

namespace schola {

namespace {

const OrtApi &ort() {
	static const OrtApi *api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
	return *api;
}

// Converts and releases an ONNX Runtime status; nullptr means success.
Status from_ort(OrtStatus *p_status, StatusCode p_code, const std::string &p_context) {
	if (p_status == nullptr) {
		return Status::ok();
	}
	std::string message = p_context + ": " + ort().GetErrorMessage(p_status);
	ort().ReleaseStatus(p_status);
	return Status::error(p_code, message);
}

struct OrtDeleter {
	void operator()(OrtSession *p_session) const { ort().ReleaseSession(p_session); }
	void operator()(OrtSessionOptions *p_options) const { ort().ReleaseSessionOptions(p_options); }
	void operator()(OrtTypeInfo *p_type_info) const { ort().ReleaseTypeInfo(p_type_info); }
};

template <typename T>
using OrtPtr = std::unique_ptr<T, OrtDeleter>;

// One environment per process. Errors come back as OrtStatus.
struct SharedEnvironment {
	OrtEnv *env = nullptr;
	Status status = Status::ok();

	SharedEnvironment() {
		status = from_ort(ort().CreateEnv(ORT_LOGGING_LEVEL_FATAL, "schola", &env), StatusCode::RUNTIME_FAILURE, "ONNX Runtime CreateEnv");
	}
	~SharedEnvironment() {
		if (env != nullptr) {
			ort().ReleaseEnv(env);
		}
	}
};

const SharedEnvironment &shared_environment() {
	static const SharedEnvironment environment;
	return environment;
}

bool starts_with(const std::string &p_text, const char *p_prefix) {
	return p_text.rfind(p_prefix, 0) == 0;
}

} // namespace

struct TensorDescription {
	std::string name;
	ONNXTensorElementDataType element_type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED;
	std::vector<int64_t> shape; // -1 for a dynamic dimension.
};

// A state is [batch, (sequence), dims...] in and [batch, dims...] out.
struct StateLayout {
	size_t input_index = 0;
	size_t output_index = 0;
	bool has_sequence = false;
	int64_t state_size = 0; // Values in one state entry.
};

struct OnnxPolicy::Impl {
	OrtPtr<OrtSession> session;
	std::string model_name;
	std::vector<TensorDescription> inputs;
	std::vector<TensorDescription> outputs;
	std::vector<std::string> input_names;
	std::vector<std::string> output_names;
	std::vector<StateLayout> states;
	int32_t max_state_sequence_length = 1;
	bool initialized = false;

	void clear_model() {
		session.reset();
		model_name.clear();
		inputs.clear();
		outputs.clear();
		input_names.clear();
		output_names.clear();
		states.clear();
		initialized = false;
	}

	Status error(StatusCode p_code, const std::string &p_message) const {
		return Status::error(p_code, "load_model(" + model_name + "): " + p_message);
	}

	Status check(OrtStatus *p_status) const {
		return from_ort(p_status, StatusCode::INVALID_DATA, "load_model(" + model_name + ")");
	}

	Status describe(bool p_inputs) {
		size_t count = 0;
		Status status = check(p_inputs ? ort().SessionGetInputCount(session.get(), &count) : ort().SessionGetOutputCount(session.get(), &count));
		OrtAllocator *allocator = nullptr;
		if (status.is_ok()) {
			status = check(ort().GetAllocatorWithDefaultOptions(&allocator));
		}

		std::vector<TensorDescription> &descriptions = p_inputs ? inputs : outputs;
		for (size_t i = 0; status.is_ok() && i < count; ++i) {
			TensorDescription description;
			char *name = nullptr;
			status = check(p_inputs ? ort().SessionGetInputName(session.get(), i, allocator, &name) : ort().SessionGetOutputName(session.get(), i, allocator, &name));
			if (!status.is_ok()) {
				break;
			}
			description.name = name;
			status = check(ort().AllocatorFree(allocator, name));

			OrtTypeInfo *raw_type_info = nullptr;
			if (status.is_ok()) {
				status = check(p_inputs ? ort().SessionGetInputTypeInfo(session.get(), i, &raw_type_info) : ort().SessionGetOutputTypeInfo(session.get(), i, &raw_type_info));
			}
			OrtPtr<OrtTypeInfo> type_info(raw_type_info);
			const OrtTensorTypeAndShapeInfo *tensor_info = nullptr;
			if (status.is_ok()) {
				status = check(ort().CastTypeInfoToTensorInfo(type_info.get(), &tensor_info));
			}
			if (status.is_ok() && tensor_info == nullptr) {
				status = error(StatusCode::INCOMPATIBLE, std::string(p_inputs ? "input '" : "output '") + description.name + "' is not a tensor");
			}

			size_t dimension_count = 0;
			if (status.is_ok()) {
				status = check(ort().GetTensorElementType(tensor_info, &description.element_type));
			}
			if (status.is_ok()) {
				status = check(ort().GetDimensionsCount(tensor_info, &dimension_count));
			}
			if (status.is_ok()) {
				description.shape.resize(dimension_count);
				status = check(ort().GetDimensions(tensor_info, description.shape.data(), dimension_count));
			}
			if (status.is_ok()) {
				descriptions.push_back(std::move(description));
			}
		}
		return status;
	}

	// Pairs state inputs with state outputs by order.
	Status find_states() {
		std::vector<size_t> state_inputs;
		std::vector<size_t> state_outputs;
		for (size_t i = 0; i < inputs.size(); ++i) {
			if (starts_with(inputs[i].name, "state_in")) {
				state_inputs.push_back(i);
			}
		}
		for (size_t i = 0; i < outputs.size(); ++i) {
			if (starts_with(outputs[i].name, "state_out")) {
				state_outputs.push_back(i);
			}
		}
		if (state_inputs.size() != state_outputs.size()) {
			return error(StatusCode::INCOMPATIBLE, std::to_string(state_inputs.size()) + " state_in tensors but " + std::to_string(state_outputs.size()) + " state_out tensors; expected one of each per state");
		}

		for (size_t pair = 0; pair < state_inputs.size(); ++pair) {
			const TensorDescription &input = inputs[state_inputs[pair]];
			const TensorDescription &output = outputs[state_outputs[pair]];
			if (input.element_type != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT || output.element_type != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT) {
				return error(StatusCode::INCOMPATIBLE, "state tensors '" + input.name + "' and '" + output.name + "' must be float");
			}
			if (input.shape.size() < 2 || output.shape.size() < 2) {
				return error(StatusCode::INCOMPATIBLE, "state tensors '" + input.name + "' and '" + output.name + "' need a batch and a state dimension");
			}

			StateLayout layout;
			layout.input_index = state_inputs[pair];
			layout.output_index = state_outputs[pair];
			layout.state_size = 1;
			for (size_t dimension = 1; dimension < input.shape.size(); ++dimension) {
				if (input.shape[dimension] > 0) {
					layout.state_size *= input.shape[dimension];
				} else if (dimension == 1) {
					layout.has_sequence = true; // A dynamic dimension right after the batch is the sequence.
				} else {
					return error(StatusCode::INCOMPATIBLE, "state input '" + input.name + "' has a dynamic dimension at index " + std::to_string(dimension) + "; only a sequence right after the batch is supported");
				}
			}

			int64_t output_size = 1;
			for (size_t dimension = 1; dimension < output.shape.size(); ++dimension) {
				if (output.shape[dimension] <= 0) {
					return error(StatusCode::INCOMPATIBLE, "state output '" + output.name + "' has a dynamic dimension besides the batch");
				}
				output_size *= output.shape[dimension];
			}
			if (output_size != layout.state_size) {
				return error(StatusCode::INCOMPATIBLE, "state output '" + output.name + "' holds " + std::to_string(output_size) + " values per entry, but '" + input.name + "' holds " + std::to_string(layout.state_size));
			}
			states.push_back(layout);
		}
		return Status::ok();
	}
};

OnnxPolicy::OnnxPolicy() :
		impl(std::make_unique<Impl>()) {}

OnnxPolicy::~OnnxPolicy() = default;

Status OnnxPolicy::load_model(const uint8_t *p_data, size_t p_size, const std::string &p_model_name) {
	impl->clear_model();
	impl->model_name = p_model_name;
	if (p_data == nullptr || p_size == 0) {
		return impl->error(StatusCode::INVALID_ARGUMENT, "no model data");
	}
	const SharedEnvironment &environment = shared_environment();
	if (!environment.status.is_ok()) {
		return environment.status;
	}

	OrtSessionOptions *raw_options = nullptr;
	Status status = from_ort(ort().CreateSessionOptions(&raw_options), StatusCode::RUNTIME_FAILURE, "load_model(" + p_model_name + ")");
	OrtPtr<OrtSessionOptions> options(raw_options);
	if (status.is_ok()) {
		status = from_ort(ort().SetIntraOpNumThreads(options.get(), 1), StatusCode::RUNTIME_FAILURE, "load_model(" + p_model_name + ")");
	}
	if (status.is_ok()) {
		status = from_ort(ort().SetInterOpNumThreads(options.get(), 1), StatusCode::RUNTIME_FAILURE, "load_model(" + p_model_name + ")");
	}
	if (status.is_ok()) {
		status = from_ort(ort().SetSessionGraphOptimizationLevel(options.get(), ORT_ENABLE_ALL), StatusCode::RUNTIME_FAILURE, "load_model(" + p_model_name + ")");
	}

	OrtSession *raw_session = nullptr;
	if (status.is_ok()) {
		status = impl->check(ort().CreateSessionFromArray(environment.env, p_data, p_size, options.get(), &raw_session));
	}
	impl->session.reset(raw_session);

	if (status.is_ok()) {
		status = impl->describe(true);
	}
	if (status.is_ok()) {
		status = impl->describe(false);
	}
	if (status.is_ok()) {
		status = impl->find_states();
	}
	if (!status.is_ok()) {
		impl->clear_model();
		return status;
	}
	for (const TensorDescription &input : impl->inputs) {
		impl->input_names.push_back(input.name);
	}
	for (const TensorDescription &output : impl->outputs) {
		impl->output_names.push_back(output.name);
	}
	return Status::ok();
}

Status OnnxPolicy::set_max_state_sequence_length(int32_t p_length) {
	if (p_length < 1) {
		return Status::error(StatusCode::INVALID_ARGUMENT, "set_max_state_sequence_length: length must be at least 1, got " + std::to_string(p_length));
	}
	if (impl->initialized) {
		return Status::error(StatusCode::FAILED_PRECONDITION, "set_max_state_sequence_length: call before init()");
	}
	impl->max_state_sequence_length = p_length;
	return Status::ok();
}

int32_t OnnxPolicy::get_max_state_sequence_length() const {
	return impl->max_state_sequence_length;
}

const std::vector<std::string> &OnnxPolicy::get_input_names() const {
	return impl->input_names;
}

const std::vector<std::string> &OnnxPolicy::get_output_names() const {
	return impl->output_names;
}

Status OnnxPolicy::init([[maybe_unused]] const InteractionDefinition &p_definition) {
	return Status::error(StatusCode::RUNTIME_FAILURE, "OnnxPolicy::init: not implemented yet");
}

Status OnnxPolicy::create_initial_state([[maybe_unused]] std::unique_ptr<PolicyState> &r_state) const {
	return Status::error(StatusCode::RUNTIME_FAILURE, "OnnxPolicy::create_initial_state: not implemented yet");
}

Status OnnxPolicy::think([[maybe_unused]] const Point &p_observation, [[maybe_unused]] PolicyState &p_state, [[maybe_unused]] Point &r_action) {
	return Status::error(StatusCode::RUNTIME_FAILURE, "OnnxPolicy::think: not implemented yet");
}

Status OnnxPolicy::batched_think(const std::vector<const Point *> &p_observations, const std::vector<PolicyState *> &p_states, const std::vector<Point *> &r_actions) {
	// One run per entry for now; a single batched run is a later optimization.
	return Policy::batched_think(p_observations, p_states, r_actions);
}

bool OnnxPolicy::is_recurrent() const {
	return !impl->states.empty();
}

bool OnnxPolicy::is_ready() const {
	return impl->session != nullptr && impl->initialized;
}

} // namespace schola
