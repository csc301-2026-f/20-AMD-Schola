# Schola for Godot: API overview

**Status:** proposal for team review. Nothing in this document is final until every affected story owner agrees.

**Differences from the current [README](../README.md):** this proposal adds folders the README does not list (`core/common`, `core/connector`, `core/policy`, `interop`, and subfolders of `bindings`), and it no longer includes US6, which the README's user-story table still lists. If this proposal is agreed, the README's directory structure and user-story table will be updated to match.

## 2. Module map

Every folder below has one owner, one purpose, and a fixed place in the build. Code goes in the folder that matches its purpose; folders are named by function, never by user story.

| Folder | Contains | Owner | Uses Godot APIs | Built into | May depend on |
| --- | --- | --- | --- | --- | --- |
| `src/core/common/` | Small types shared by every module, such as the error type and IDs | Shared | No | both | none |
| `src/core/spaces/` | Space and point types | US2 | No | both | `core/common` |
| `src/core/environment/` | Agent and environment contracts | US1 | No | both | `core/common`, `core/spaces` |
| `src/core/lifecycle/` | Step, reset, and auto-reset coordination; multiple environments | US4 | No | both | `core/common`, `core/spaces`, `core/environment` |
| `src/core/connector/` | Connector interface: the training-time source of actions | US3 | No | both | `core/common`, `core/spaces`, `core/environment`, `core/lifecycle` |
| `src/core/policy/` | Policy interface and steppers: the inference-time source of actions | US7 | No | both | `core/common`, `core/spaces`, `core/environment` |
| `src/inference/` | ONNX Runtime implementation of the policy interface | US7 | No | `schola` | `core`, ONNX Runtime |
| `src/interop/` | Conversion between core types and Godot `Variant` values; registers no classes | US2, with US4 for training data | Yes | both | `core` |
| `src/bindings/environment/` | Environment and agent nodes shown in the editor | US1 for developer-facing behaviour, US5 for editor-facing parts (see [4.4](#44-environment-nodes-and-space-resources-srcbindingsenvironment-us1-us5-srcbindingsspaces-us2)) | Yes | `schola` | `core`, `interop` |
| `src/bindings/lifecycle/` | `ScholaTrainingHost`: runs the environment lifecycle for the training extension | US4 | Yes | `schola` | `core`, `interop`, `bindings/environment` |
| `src/bindings/spaces/` | Inspector resources for declaring spaces | US2, with US5 | Yes | `schola` | `core/spaces`, `interop` |
| `src/bindings/inference/` | Policy resource and inference stepper node | US7 | Yes | `schola` | `core`, `interop`, `inference`, `bindings/environment` |
| `src/transport/proto/` | Protobuf conversion of spaces, points, interaction definitions, and agent states | US2 | No | `schola_training` | `core`, `generated/proto`, protobuf |
| `src/transport/grpc/` | gRPC implementation of the connector interface and protobuf conversion of training messages | US3 | No | `schola_training` | `core`, `transport/proto`, `generated/proto`, gRPC, protobuf |
| `src/training/` | Training extension entry point and training-only Godot classes (`training/bindings/`) | US3 | Registration and training classes only | `schola_training` | `core`, `interop`, `transport` |
| `src/runtime/` | Runtime extension entry point | Shared | Registration only | `schola` | `bindings`, `inference` |
| `generated/proto/` | Generated protobuf and gRPC sources, never edited by hand | US3 | No | `schola_training` | protobuf, gRPC |
| `thirdparty/onnxruntime/` | Downloaded ONNX Runtime package, checksum-verified and ignored by Git | US7 | n/a | `schola` | n/a |
| `tests/unit/<module>/` | Catch2 tests, one subfolder per tested module | Module owner | No | test program | module under test |
| `tests/integration/<module>/` | GdUnit4 tests, one subfolder per tested module | Module owner | Yes | n/a | n/a |
| `examples/basic_environment/` | Demonstration scene for training and inference | US5, with US7 for inference | Yes | n/a | n/a |
| `addons/schola/`, `addons/schola_training/` | Extension descriptors and built libraries | Shared; US7 owns export rules | n/a | n/a | n/a |

### The two extensions

| Extension | Folders compiled in | Ships in exported games |
| --- | --- | --- |
| `schola` (runtime) | `core`, `interop`, `inference`, `bindings`, `runtime` | Yes |
| `schola_training` | `core`, `interop`, `transport`, `training`, `generated/proto` | No, excluded on export |

`core` and `interop` are compiled into both extensions. Neither registers Godot classes, so nothing is registered twice. Adding `src/interop` to both targets is a shared-infrastructure change to `SConstruct` and lands in its own pull request. Godot-facing classes register through one hook per area:

| Hook | Registers classes from |
| --- | --- |
| `src/bindings/register_types` | `bindings/environment/`, `bindings/spaces/`, `bindings/lifecycle/` |
| `src/inference/register_types` | `bindings/inference/` |
| `src/training/bindings/register_types` | `training/bindings/` |

### Dependency direction

```text
Training extension                      Runtime extension

training ─ ─ Godot method calls ─ ─ ─► bindings/lifecycle ──► bindings/environment
   │                                          │                       │
   ▼                                          ▼                       ▼
transport/grpc                          core/lifecycle ──────► core/environment ◄── core/policy ◄── inference ◄── bindings/inference
   │                                          ▲                       │
   ▼                                          │                       ▼
core/connector ───────────────────────────────┘                 core/spaces ──► core/common
```

Solid arrows point from a module to the modules it uses. The dashed arrow is a call through Godot's object system at run time, not a compile-time dependency. Not drawn:

- `bindings/spaces` uses `core/spaces`; `bindings/inference` also uses `bindings/environment`.
- `transport/grpc` uses `transport/proto`, which uses `core` and the generated protobuf classes.
- `interop` is compiled into both extensions and uses `core`. It is used by `training`, `bindings/lifecycle`, `bindings/environment`, `bindings/spaces`, and `bindings/inference`.

Rules:

- `core` never depends on `bindings`, `inference`, `transport`, `training`, Godot, gRPC, protobuf, or ONNX Runtime.
- Runtime folders never depend on training folders. A shipped game contains no training code.
- `core/connector` and `core/policy` do not depend on each other: the agent does not know whether its actions come from Python or from a model.
- The training extension never uses runtime C++ classes directly. It reaches the runtime through one Godot object, `ScholaTrainingHost`, by calling its bound methods with `Variant` arguments (see [4.5](#45-training-host-srcbindingslifecycle-us4) and the [development contract](development_contract.md#c-conventions)).

### Mapping to the Unreal plugin

The layout keeps the separation AMD uses in the Unreal plugin, adapted to the README rule that abstractions live in `core`.

| Unreal module | Contents | Godot location |
| --- | --- | --- |
| `Schola` | Agent, policy interface, spaces, points | `core/environment`, `core/policy`, `core/spaces` |
| `ScholaTraining` | Environment interfaces, connector abstractions, auto-reset types | `core/environment`, `core/connector`, `core/lifecycle` |
| `ScholaInferenceUtils` | Steppers | `core/policy` |
| `ScholaNNE` | Neural-network policy | `inference` |
| `ScholaProtobuf` | gRPC connector, protobuf conversion | `transport/grpc`, `transport/proto`, `generated/proto` |

### Naming

- Folders are named by purpose (`environment`, `inference`), never by user story.
- Engine-independent code uses `namespace schola`.
- Godot classes are global and prefixed with `Schola`, for example `ScholaAgent`.
- File names use `snake_case`; types use `PascalCase` (see the [development contract](development_contract.md)).

## 3. Shared data types

These types are used by more than one story. Changing any of them requires review from every story listed as a user.

Conventions for every C++ API in this document:

- Functions that can fail return `Status`. Data they produce is written to parameters prefixed `r_`; inputs are prefixed `p_`, following godot-cpp.
- Containers keyed by ID use `std::map`, so iteration order is deterministic.
- Callers keep output containers (`r_` maps, vectors, and points) between steps, and implementations update their existing entries in place, so a step with unchanged agents and sizes performs no heap allocation.
- Declarations are listed in reading order. Real headers may order them differently, for example to resolve the `Space`/`DictSpace` recursion.

### 3.1 Errors: `core/common/status.h` (shared)

```cpp
namespace schola {

enum class StatusCode {
	OK,
	INVALID_ARGUMENT,    // The caller broke a documented precondition, e.g. passed a point of the wrong kind.
	NOT_FOUND,           // A required resource is missing, e.g. a model file or an agent ID.
	INVALID_DATA,        // Data exists but cannot be parsed, e.g. a corrupt ONNX file or a malformed Variant.
	INCOMPATIBLE,        // Valid data contradicts a declaration, e.g. model inputs that differ from the agent's spaces.
	FAILED_PRECONDITION, // Called in the wrong state, e.g. step() before initialize().
	TIMEOUT,             // A blocking wait expired, e.g. no message from Python in time.
	CLOSED,              // The other side shut down, e.g. Python closed the connection.
	RUNTIME_FAILURE,     // A third-party library failed, e.g. ONNX Runtime or gRPC.
};

class [[nodiscard]] Status {
public:
	static Status ok();                                            // Success.
	static Status error(StatusCode p_code, std::string p_message); // Failure; the message says what failed and how to fix it.
	bool is_ok() const;                                            // True for StatusCode::OK.
	StatusCode get_code() const;                                   // For tests and control flow.
	const std::string &get_message() const;                        // For developers; shown by Godot-facing bindings.
};

} // namespace schola
```

Users: every story.

### 3.2 Identifiers: `core/common/types.h` (shared)

```cpp
namespace schola {

using AgentId = std::string;                     // Unique within its environment; the key of protobuf agent maps.
using EnvironmentId = int32_t;                   // Index of the environment in TrainingDefinition::environments.

} // namespace schola
```

Users: US1, US3, US4.

### 3.3 Spaces: `core/spaces/space.h` (US2)

A space describes the shape and valid range of observations or actions. `Space` is a value type: copying it copies the definition.

```cpp
namespace schola {

enum class SpaceKind { BOX, DISCRETE, MULTI_DISCRETE, MULTI_BINARY, DICT };

// Element type of a Box, with the same values as Proto/DType.proto.
enum class DType { FLOAT32, UINT8, UINT16, UINT32, UINT64, INT8, INT16, INT32, INT64, FLOAT16, FLOAT64, BOOL };

struct BoxSpace {
	std::vector<float> low;       // Lower bound per element, row-major; -INFINITY means unbounded.
	std::vector<float> high;      // Upper bound per element; +INFINITY means unbounded.
	std::vector<int32_t> shape;   // Dimensions, e.g. {4} or {3, 64, 64}; their product equals low.size().
	DType dtype = DType::FLOAT32; // Element type Python sees, e.g. UINT8 for camera images. Values are stored as float.
};

struct DiscreteSpace {
	int32_t n = 0; // Valid values are 0 .. n-1 (protobuf field `high`).
};

struct MultiDiscreteSpace {
	std::vector<int32_t> nvec; // Element i takes values 0 .. nvec[i]-1 (protobuf field `high`).
};

struct MultiBinarySpace {
	int32_t n = 0; // Number of elements, each 0 or 1 (protobuf field `shape`).
};

struct DictSpace {
	std::vector<std::pair<std::string, Space>> entries; // Sub-spaces sorted by key, matching gymnasium.spaces.Dict.
	const Space *find(const std::string &p_key) const;  // The sub-space for a key, or nullptr.
};

class Space {
public:
	Space();                            // Empty Box space; a placeholder until assigned.
	Space(BoxSpace p_space);            // Implicit conversion from each kind.
	Space(DiscreteSpace p_space);
	Space(MultiDiscreteSpace p_space);
	Space(MultiBinarySpace p_space);
	Space(DictSpace p_space);

	SpaceKind get_kind() const;         // Which kind this space holds.
	template <typename T>
	const T *get_if() const;            // e.g. space.get_if<BoxSpace>(); nullptr for another kind.

	Status check_definition() const;                        // OK, or why the definition is invalid: low > high, size/shape mismatch, n <= 0, duplicate Dict key, bounds outside the dtype's range.
	Status validate_structure(const Point &p_point) const;  // INVALID_ARGUMENT for a wrong kind, wrong size, missing Dict key, non-integer value for an integer dtype, or a Discrete, MultiDiscrete, or MultiBinary value outside its range.
	Status validate_bounds(const Point &p_point) const;     // INVALID_ARGUMENT for a Box value outside low/high; names the element index and value. Assumes valid structure.
	Status validate(const Point &p_point) const;            // validate_structure(), then validate_bounds().
	Point make_point() const;                     // Zero-filled point of this kind and size; allocate once and reuse every step.
	int64_t get_flattened_size() const;           // Number of scalars; Discrete counts 1, Dict sums its entries.
	std::string to_string() const;                // Short description for diagnostics, e.g. "Box(shape=[4], low=-1, high=1)".
};

} // namespace schola
```

Users: every story. Text spaces from `Spaces.proto` are not supported in the MVP; the Unreal plugin's ONNX inference does not support them either.

Box data types:

- Every `DType` in `Proto/DType.proto` is supported. Schola's Python package already maps each one to a NumPy type (`deserialize.py`), so Python builds `gymnasium.spaces.Box` with the declared type. The Unreal plugin never sets this field, so it always sends `FLOAT32`; the default matches it.
- Values are stored as `float` in `BoxPoint`, because `BoxPoint.values` in `Points.proto` is a list of floats. Integer values above 2^24, and `INT64`, `UINT64`, and `FLOAT64` values that need more precision than float32, cannot be represented exactly. This is a limit of the existing protocol.
- For integer types and `BOOL`, every value must be a whole number inside the type's range, and `BOOL` values must be 0 or 1. `validate_structure()` rejects other values.

Validation is split in two so callers can treat the cases differently (see [validation](#validation-of-actions-and-observations)): a structural mismatch always means a bug, while a value slightly outside its Box bounds can be normal reinforcement-learning behaviour.

### 3.4 Points: `core/spaces/point.h` (US2)

A point is one value in a space: one observation or one action. `Point` is a value type.

```cpp
namespace schola {

struct BoxPoint {
	std::vector<float> values;  // Row-major; size equals the product of shape.
	std::vector<int32_t> shape; // Same as the space's shape.
};

struct DiscretePoint {
	int32_t value = 0;
};

struct MultiDiscretePoint {
	std::vector<int32_t> values; // One value per nvec entry.
};

struct MultiBinaryPoint {
	std::vector<uint8_t> values; // Each 0 or 1; not std::vector<bool>, so the data stays contiguous.
};

struct DictPoint {
	std::vector<std::pair<std::string, Point>> entries; // Sorted by key; same keys as the DictSpace.
	Point *find(const std::string &p_key);              // The sub-point for a key, or nullptr.
	const Point *find(const std::string &p_key) const;
};

class Point {
public:
	Point();                           // Empty BoxPoint.
	Point(BoxPoint p_point);           // Implicit conversion from each kind.
	Point(DiscretePoint p_point);
	Point(MultiDiscretePoint p_point);
	Point(MultiBinaryPoint p_point);
	Point(DictPoint p_point);

	SpaceKind get_kind() const;        // Which kind this point holds.
	template <typename T>
	T *get_if();                       // e.g. point.get_if<BoxPoint>(); nullptr for another kind.
	template <typename T>
	const T *get_if() const;
	std::string to_string() const;     // Values for diagnostics, e.g. "[0.1, -0.5]".
};

} // namespace schola
```

Users: every story. Integers are 32-bit, matching `Points.proto` and the Unreal plugin; US7 converts to the 64-bit integers used by ONNX models.

### 3.5 Godot values: `interop/` (US2; training data with US4)

Godot code and GDScript represent points with these `Variant` types:

| Space kind | GDScript type | Example |
| --- | --- | --- |
| Box | `PackedFloat32Array` (row-major), for every `dtype` | `PackedFloat32Array([0.1, -0.5, 0.0, 1.0])` |
| Discrete | `int` | `2` |
| MultiDiscrete | `PackedInt32Array` | `PackedInt32Array([1, 0, 3])` |
| MultiBinary | `PackedByteArray` (each 0 or 1) | `PackedByteArray([1, 0, 1])` |
| Dict | `Dictionary` (String to value) | `{"position": PackedFloat32Array([...]), "mode": 1}` |

Across the extension boundary, spaces travel as dictionaries:

| Space kind | Dictionary |
| --- | --- |
| Box | `{"kind": "box", "low": PackedFloat32Array, "high": PackedFloat32Array, "shape": PackedInt32Array, "dtype": String}` (`INF` and `-INF` for unbounded; `dtype` is the `DType` name in lower case, e.g. `"uint8"`) |
| Discrete | `{"kind": "discrete", "n": int}` |
| MultiDiscrete | `{"kind": "multi_discrete", "nvec": PackedInt32Array}` |
| MultiBinary | `{"kind": "multi_binary", "n": int}` |
| Dict | `{"kind": "dict", "spaces": {String: <space dictionary>}}` |

`interop/variant_conversion.h`:

```cpp
namespace schola {

Status variant_to_point(const godot::Variant &p_value, const Space &p_space, Point &r_point); // Converts a GDScript value; INVALID_ARGUMENT names the expected type and size.
godot::Variant point_to_variant(const Point &p_point);                                        // Converts a point to its GDScript form.
Status variant_to_space(const godot::Variant &p_value, Space &r_space);                       // Parses a space dictionary.
godot::Variant space_to_variant(const Space &p_space);                                        // Produces a space dictionary.

} // namespace schola
```

`interop/training_variant.h` (US4) converts the training types from [4.2](#42-lifecycle-srccorelifecycle-us4) to and from the formats in [4.5](#45-training-host-srcbindingslifecycle-us4):

```cpp
namespace schola {

godot::Variant training_definition_to_variant(const TrainingDefinition &p_definition);
Status variant_to_training_definition(const godot::Variant &p_value, TrainingDefinition &r_definition);
godot::Variant reset_request_to_variant(const ResetRequest &p_request);
Status variant_to_reset_request(const godot::Variant &p_value, ResetRequest &r_request);
godot::Variant step_request_to_variant(const StepRequest &p_request);
Status variant_to_step_request(const godot::Variant &p_value, const TrainingDefinition &p_definition, StepRequest &r_request); // Uses the definition to type each action.
godot::Variant training_state_to_variant(const TrainingState &p_state);
Status variant_to_training_state(const godot::Variant &p_value, const TrainingDefinition &p_definition, TrainingState &r_state);
godot::Variant initial_state_to_variant(const InitialState &p_state);
Status variant_to_initial_state(const godot::Variant &p_value, const TrainingDefinition &p_definition, InitialState &r_state);

} // namespace schola
```

### 3.6 Protobuf form: `transport/proto/proto_conversion.h` (US2)

Converts the shared types to and from the messages in `Proto/`, which the existing Python package expects. It lives in the training extension because protobuf is never linked into the runtime. Generated classes are in namespace `::Schola`, because every `.proto` file declares `package Schola;`.

```cpp
namespace schola {

void to_proto(const Space &p_space, ::Schola::Space &r_message);                                 // Box bounds of ±INFINITY are written as unset (unbounded); dtype is written to BoxSpace.dtype.
Status from_proto(const ::Schola::Space &p_message, Space &r_space);                             // INVALID_DATA for Text spaces, an empty oneof, or inconsistent sizes. Dict keys are sorted.
void to_proto(const Point &p_point, ::Schola::Point &r_message);
Status from_proto(const ::Schola::Point &p_message, Point &r_point);                             // INVALID_DATA for Text points or an empty oneof. Dict keys are sorted.
void to_proto(const InteractionDefinition &p_definition, ::Schola::AgentDefinition &r_message);
Status from_proto(const ::Schola::AgentDefinition &p_message, InteractionDefinition &r_definition);
void to_proto(const AgentState &p_state, ::Schola::AgentState &r_message);
Status from_proto(const ::Schola::AgentState &p_message, AgentState &r_state);
void to_proto(const InitialAgentState &p_state, ::Schola::InitialAgentState &r_message);
Status from_proto(const ::Schola::InitialAgentState &p_message, InitialAgentState &r_state);

} // namespace schola
```

Conversion to protobuf cannot fail, because every core value has a protobuf form. Conversion from protobuf returns `Status`, because messages from outside can be malformed. Training only needs to convert spaces, definitions, and states to protobuf, and points (actions) back from it. The remaining directions exist for US2's round-trip tests, which convert every type to protobuf and back and check that its values do not change. These tests need the protobuf library, so they cannot run until US3 selects the gRPC and protobuf versions.

## 4. API by module

### 4.1 Agent and environment: `src/core/environment/` (US1)

Training goes through the environment, which reports reward and done flags for every agent (Unreal: `IScholaEnvironment`). Inference goes through the agent alone (Unreal: `IAgent`).

`interaction_definition.h`:

```cpp
namespace schola {

struct InteractionDefinition {
	Space observation_space;
	Space action_space;
	std::string agent_type; // Optional. Agents with the same type may share one policy in training; empty means the agent ID.
};

} // namespace schola
```

`agent.h`:

```cpp
namespace schola {

class Agent {
public:
	virtual ~Agent() = default;
	virtual Status define(InteractionDefinition &r_definition) = 0; // Declares the agent's spaces; called once before observe() and act().
	virtual Status observe(Point &r_observation) = 0;               // Fills a point made by observation_space.make_point().
	virtual Status act(const Point &p_action) = 0;                  // Applies one action from the action space.
};

} // namespace schola
```

`environment.h`:

```cpp
namespace schola {

struct ResetSettings {
	std::optional<int32_t> seed;                // Set when Python passes a seed to reset().
	std::map<std::string, std::string> options; // Python's reset(options=...), as strings.
};

struct InitialAgentState {
	Point observation;                       // First observation of the episode.
	std::map<std::string, std::string> info; // Free-form data for Python's `info` dict.
};

struct AgentState {
	Point observation;       // Observation after the actions were applied.
	float reward = 0.0f;     // Reward for this step.
	bool terminated = false; // The episode ended for this agent, e.g. goal reached or failure.
	bool truncated = false;  // The episode was cut short, e.g. a time limit.
	std::map<std::string, std::string> info; // Free-form data for Python's `info` dict.
};

class Environment {
public:
	virtual ~Environment() = default;
	virtual Status initialize(std::map<AgentId, InteractionDefinition> &r_agents) = 0;                       // Declares every agent and its spaces; called once before the first reset.
	virtual Status reset(const ResetSettings &p_settings, std::map<AgentId, InitialAgentState> &r_states) = 0; // Starts a new episode and reports each agent's first observation.
	virtual Status step(const std::map<AgentId, Point> &p_actions, std::map<AgentId, AgentState> &r_states) = 0; // Applies the actions, then reports one AgentState per agent in p_actions.
};

} // namespace schola
```

`p_actions` contains only agents that are still running; the lifecycle filters out finished agents.

### 4.2 Lifecycle: `src/core/lifecycle/` (US4)

`training_types.h` mirrors the protobuf messages without depending on protobuf:

```cpp
namespace schola {

enum class AutoResetMode { SAME_STEP, NEXT_STEP, DISABLED }; // protobuf AutoResetType; Python chooses it at start.

struct EnvironmentDefinition {
	std::map<AgentId, InteractionDefinition> agents;
};

struct TrainingDefinition {
	std::vector<EnvironmentDefinition> environments; // Index is the EnvironmentId.
};

struct StepRequest {
	std::vector<std::map<AgentId, Point>> actions; // One map per environment; index is the EnvironmentId.
};

struct ResetRequest {
	std::map<EnvironmentId, ResetSettings> environments; // Only the environments to reset.
};

struct EnvironmentState {
	std::map<AgentId, AgentState> agents;
};

struct TrainingState {
	std::vector<EnvironmentState> environments; // Every environment, every step.
};

struct InitialState {
	std::map<EnvironmentId, std::map<AgentId, InitialAgentState>> environments; // Only environments that were reset.
};

} // namespace schola
```

`training_backend.h`:

```cpp
namespace schola {

// What the connector loop drives. Implemented by EnvironmentRunner in the runtime extension and by a
// proxy to ScholaTrainingHost in the training extension.
class TrainingBackend {
public:
	virtual ~TrainingBackend() = default;
	virtual Status define(TrainingDefinition &r_definition) = 0;                                                 // Every environment's agents and spaces.
	virtual Status set_autoreset_mode(AutoResetMode p_mode) = 0;                                                 // Called once, before the first reset.
	virtual Status reset(const ResetRequest &p_request, InitialState &r_initial_state) = 0;                      // Resets the listed environments.
	virtual Status step(const StepRequest &p_request, TrainingState &r_state, InitialState &r_initial_state) = 0; // Steps every environment; r_initial_state lists environments auto-reset in this step.
};

} // namespace schola
```

`environment_runner.h`:

```cpp
namespace schola {

class EnvironmentRunner final : public TrainingBackend {
public:
	Status set_environments(std::vector<Environment *> p_environments); // Non-owning; index becomes the EnvironmentId. Calls initialize() on each.
	void set_strict_bounds(bool p_strict);                              // true: out-of-bounds actions fail the step. Default false: they produce a warning.
	std::vector<std::string> take_warnings();                           // Bounds warnings collected since the last call; the host reports each with push_warning.

	Status define(TrainingDefinition &r_definition) override;
	Status set_autoreset_mode(AutoResetMode p_mode) override;
	Status reset(const ResetRequest &p_request, InitialState &r_initial_state) override;
	Status step(const StepRequest &p_request, TrainingState &r_state, InitialState &r_initial_state) override;
};

} // namespace schola
```

Step behaviour, matching Unreal's `UAbstractGymConnector::HandleStep`:

- An environment is done when all of its agents are terminated or truncated.
- `SAME_STEP`: a done environment is reset in the same step, and its first observations are returned in `r_initial_state`.
- `NEXT_STEP`: a done environment is reset on the following step instead of stepping; its agents report the new observation with reward 0.
- `DISABLED`: a done environment stays done until Python sends a reset.
- Actions for agents that already finished are ignored, and their last state is reported again.
- Environments step sequentially on the main thread.

#### Validation of actions and observations

Every value crossing a boundary is checked against its declared space. A structural mismatch always fails; a Box value outside its bounds produces a warning unless strict bounds are enabled.

| Value | Checked by | Structure (`validate_structure`) | Box bounds (`validate_bounds`) |
| --- | --- | --- | --- |
| Action from Python | `EnvironmentRunner::step`, before `Environment::step` | Fails the step with `INVALID_ARGUMENT`; training ends with the error | Warning, or `INVALID_ARGUMENT` with strict bounds |
| Observation from `_observe()` | The `ScholaAgent` adapter (4.4), in training and inference | Fails with `INVALID_ARGUMENT`, reported with `push_error` | Warning, or `INVALID_ARGUMENT` with strict bounds |
| Action from an ONNX model | `OnnxPolicy::init`, once, by checking the model's output types and shapes | Not checked per step | Not checked |

Rules:

- Messages name the environment, agent, value (action or observation), and reason, e.g. `Environment 0, agent "runner": action is outside its Box bounds at index 1 (1.7 > high 1.0).`
- Each bounds warning is reported once per agent and value, not on every step.
- The project setting `schola/validation/strict_bounds` (default `false`) turns bounds warnings into errors.
- Bounds are lenient by default because reinforcement-learning libraries can legitimately send slightly out-of-bounds Box actions: RLlib does not clip actions by default (`clip_actions = False`), while Stable-Baselines3 clips them. The Unreal plugin performs no validation at all.

### 4.3 Connector: `src/core/connector/` (US3)

```cpp
namespace schola {

struct StartRequest {
	AutoResetMode autoreset_mode = AutoResetMode::SAME_STEP;
};

enum class UpdateKind { STEP, RESET, CLOSE };

struct ConnectorUpdate {
	UpdateKind kind = UpdateKind::STEP;
	StepRequest step;   // Valid when kind is STEP.
	ResetRequest reset; // Valid when kind is RESET.
};

// The training-time source of actions. Implemented by GrpcConnector; tests use fakes.
class Connector {
public:
	virtual ~Connector() = default;
	virtual Status open(const TrainingDefinition &p_definition) = 0;                                   // Starts listening and serves the definition to Python.
	virtual Status wait_for_start(StartRequest &r_request, std::chrono::milliseconds p_timeout) = 0;   // Blocks until Python starts the connector; TIMEOUT otherwise.
	virtual Status wait_for_update(ConnectorUpdate &r_update, std::chrono::milliseconds p_timeout) = 0; // Blocks the main thread until Python's next message. TIMEOUT after p_timeout (zero waits indefinitely); CLOSED if Python reported an error.
	virtual Status poll_update(ConnectorUpdate &r_update) = 0;                                         // Never blocks. OK with an update if one has arrived, NOT_FOUND if not yet; CLOSED as for wait_for_update.
	virtual Status reply(const TrainingState *p_state, const InitialState *p_initial_state) = 0;       // Answers the last update; nullptr leaves that field unset.
	virtual void close() = 0;                                                                          // Stops listening and joins worker threads; safe to call twice.
};

// The README's engine-independent connector loop.
class ConnectorLoop {
public:
	Status start(Connector &p_connector, TrainingBackend &p_backend, std::chrono::milliseconds p_start_timeout); // define, open, wait_for_start, then set_autoreset_mode.
	Status tick(std::chrono::milliseconds p_update_timeout);                                                     // Headless mode, one physics frame: wait for an update, run it on the backend, reply. CLOSED when Python disconnects.
	Status poll_tick(std::chrono::milliseconds p_update_timeout);                                                // Windowed mode: if an update has arrived, run it and reply; otherwise return NOT_FOUND at once. TIMEOUT once no update has arrived for p_update_timeout.
	void stop();                                                                                                 // Closes the connector.
};

} // namespace schola
```

Replies: after a reset, only `p_initial_state`; after a step, `p_state`, plus `p_initial_state` when environments were auto-reset in `SAME_STEP` mode.

### 4.4 Environment nodes and space resources: `src/bindings/environment/` (US1, US5), `src/bindings/spaces/` (US2)

Users build environments from nodes and override virtual methods in GDScript (godot-cpp `GDVIRTUAL`). An environment's agents are its `ScholaAgent` descendants. `ScholaEnvironment` supplies lifecycle hooks, not a goal-condition or reward-rule language: game-specific behaviour stays in the user's Godot scripts and composable helper components.

Ownership of `ScholaEnvironment` and `ScholaAgent` is split by audience:

- **US1, developer-facing behaviour:** the virtual methods (`_reset_episode`, `_get_reward`, `_is_terminated`, `_is_truncated`, `_get_info`, `_observe`, `_act`), `get_agents()`, `get_episode_step()`, the signals, the step order, and the core adapters returned by `get_environment()` and `get_agent()`.
- **US5, editor-facing parts:** the `@export` properties shown in the Inspector, the [configuration checks](#configuration-checks), the editor plugin, and the demonstration scene.

```gdscript
class_name ScholaEnvironment extends Node
@export var max_episode_steps: int = 0                         # 0 means no limit; otherwise agents are truncated after this many steps.
func _reset_episode(seed: Variant, options: Dictionary) -> void # Virtual. seed is an int or null. Return the scene to a start state.
func _get_reward(agent: ScholaAgent) -> float                  # Virtual. Reward for the step that just ran.
func _is_terminated(agent: ScholaAgent) -> bool                # Virtual. Default false.
func _is_truncated(agent: ScholaAgent) -> bool                 # Virtual. Default false; max_episode_steps applies on top.
func _get_info(agent: ScholaAgent) -> Dictionary               # Virtual. Optional String-to-String data for Python.
func get_agents() -> Array[ScholaAgent]                        # Agents in scene-tree order.
func get_episode_step() -> int                                 # Steps since the last reset.
func get_rng() -> RandomNumberGenerator                        # This environment's random generator; use it for all episode randomness.
func _get_configuration_warnings() -> PackedStringArray        # Editor warning icon; returns get_configuration_errors().
signal episode_started
signal episode_ended

class_name ScholaAgent extends Node
@export var agent_id: String = ""            # Empty means the node name. Unique within the environment.
@export var agent_type: String = ""          # See InteractionDefinition::agent_type.
@export var observation_space: ScholaSpace
@export var action_space: ScholaSpace
func _observe() -> Variant                   # Virtual. Returns a value in the GDScript form of the observation space (3.5).
func _act(action: Variant) -> void           # Virtual. Receives a value in the GDScript form of the action space.
func _get_configuration_warnings() -> PackedStringArray # Editor warning icon; returns get_configuration_errors().
```

C++ accessors used by other runtime modules (same extension, so direct calls are safe):

```cpp
schola::Environment *ScholaEnvironment::get_environment(); // Core adapter over this node; valid while the node is in the tree.
schola::Agent *ScholaAgent::get_agent();                   // Core adapter over this node; valid while the node is in the tree.

godot::PackedStringArray ScholaEnvironment::get_configuration_errors() const; // Configuration problems of this node; empty when valid.
godot::PackedStringArray ScholaAgent::get_configuration_errors() const;       // Configuration problems of this node; empty when valid.
```

`ScholaEnvironment::step()` calls `_act` on every agent with an action, then `_observe`, `_get_reward`, `_is_terminated`, `_is_truncated`, and `_get_info` on each of them. Invalid return values are reported once with `push_error` and fail the step with `INVALID_ARGUMENT`. The agent adapter checks every `_observe()` result against the observation space as described in [validation](#validation-of-actions-and-observations).

`get_rng()` makes episodes reproducible, with the same seeding rules as Gymnasium (verified with `gymnasium` 1.2):

- Each environment owns one `RandomNumberGenerator`, randomized when the environment is created.
- A reset with a seed re-seeds it before `_reset_episode` runs.
- A reset without a seed (`seed` is `null`) keeps the current stream, so `reset(seed=5)` followed by any number of `reset()` calls always produces the same sequence.
- Environments do not share a generator, so several environments in one scene do not affect each other.

Randomness drawn from Godot's global functions such as `randf()` is not covered. Physics simulation is not guaranteed to be bit-identical between runs.

#### Configuration checks

Each node checks its own configuration in one function, `get_configuration_errors()`, so the checks are written once and used in two places:

- **In the editor:** `_get_configuration_warnings()` returns the same list, and Godot shows a warning icon on the node in the scene tree without running the game. Property setters call `update_configuration_warnings()` so the icon refreshes immediately.
- **When the scene runs:** `Environment::initialize()` and `Agent::define()` fail with `INVALID_ARGUMENT` and a message listing every problem, which the bindings report once with `push_error`.

`Status` (3.1) carries the run-time failure; this function decides what counts as a failure.

| Node | Problem reported |
| --- | --- |
| `ScholaEnvironment` | It has no `ScholaAgent` descendants. |
| `ScholaEnvironment` | Two agents use the same `agent_id`; the message names both nodes. |
| `ScholaEnvironment` | `max_episode_steps` is negative. |
| `ScholaEnvironment` | It contains another `ScholaEnvironment`, so agent ownership is ambiguous. |
| `ScholaAgent` | `observation_space` or `action_space` is not set. |
| `ScholaAgent` | A space is invalid; the message includes the reason from `Space::check_definition()`, e.g. `low > high` or `n <= 0`. |

Space resources, edited in the Inspector:

```gdscript
class_name ScholaSpace extends Resource                    # Abstract base.
func get_validation_error(value: Variant) -> String        # Empty if value belongs to the space; otherwise why not.

class_name ScholaBoxSpace extends ScholaSpace
@export var low: PackedFloat32Array
@export var high: PackedFloat32Array
@export var shape: PackedInt32Array                          # Empty means [low.size()].
@export var dtype: int = DType.FLOAT32                       # Enum with the values of Proto/DType.proto, shown as a drop-down in the Inspector.

class_name ScholaDiscreteSpace extends ScholaSpace
@export var n: int

class_name ScholaMultiDiscreteSpace extends ScholaSpace
@export var nvec: PackedInt32Array

class_name ScholaMultiBinarySpace extends ScholaSpace
@export var n: int

class_name ScholaDictSpace extends ScholaSpace
@export var spaces: Dictionary                              # String to ScholaSpace.
```

```cpp
schola::Space ScholaSpace::to_space() const; // Core space for this resource.
```

#### Basic environment demonstration (US5)

`examples/basic_environment/` is an MVP demonstration of the public node API, not a special case in `ScholaEnvironment`. Its scene configures a movement agent and uses a demo-specific script or helper component to calculate and visibly report the reward for each step:

- moving backward receives a small reward;
- moving forward receives a larger reward; and
- remaining still receives a penalty.

The demo-specific component may expose those three values as Inspector properties. They must not become exported properties of generic `ScholaEnvironment`, which remains reusable for environments with different reward functions. The demonstration also exposes `max_episode_steps`; when it is positive, the normal lifecycle reports an otherwise unfinished episode as truncated. Tests cover forward, backward, stationary, reset, and maximum-step behaviour.

### 4.5 Training host: `src/bindings/lifecycle/` (US4)

`ScholaTrainingHost` is the single runtime object the training extension talks to. `addons/schola/` contains a small scene whose root is a `ScholaTrainingHost` node, and the add-on's [editor plugin](#editor-plugin) adds that scene as an autoload when the plugin is enabled. The host is harmless in shipped games: without the training extension it does nothing.

```gdscript
class_name ScholaTrainingHost extends Node
func define() -> Dictionary                        # {"error": String, "definition": <TrainingDefinition>}
func set_autoreset_mode(mode: int) -> Dictionary   # mode: 0 SAME_STEP, 1 NEXT_STEP, 2 DISABLED. Returns {"error": String}.
func reset(request: Dictionary) -> Dictionary      # <ResetRequest> to {"error": String, "initial_state": <InitialState>}
func step(actions: Array) -> Dictionary            # <StepRequest> to {"error": String, "state": <TrainingState>, "initial_state": <InitialState>}
```

`"error"` is empty on success. `define()` collects every `ScholaEnvironment` in the current scene in scene-tree order; that order is the `EnvironmentId`.

Startup: in `_ready()`, if `ClassDB.class_exists("ScholaTrainingConnector")` and training is requested (`-ScholaPort=<n>` in `OS.get_cmdline_user_args()`, or the project setting `schola/training/listen_in_editor`), the host instantiates `ScholaTrainingConnector` by class name and adds it as a child. If `-ScholaScene=<res://path.tscn>` is also given, the host first changes to that scene. The host passes the project setting `schola/validation/strict_bounds` to `EnvironmentRunner::set_strict_bounds` and reports `EnvironmentRunner::take_warnings()` after each step with `push_warning`. Otherwise it does nothing. This keeps the runtime free of compile-time dependencies on training code.

Data formats (points and spaces as in [3.5](#35-godot-values-interop-us2-training-data-with-us4)):

| Type | Format |
| --- | --- |
| TrainingDefinition | `Array`, one entry per environment: `{agent_id: {"observation_space": <space>, "action_space": <space>, "agent_type": String}}` |
| ResetRequest | `{env_id: {"seed": int or null, "options": {String: String}}}` |
| InitialState | `{env_id: {agent_id: {"observation": <point>, "info": {String: String}}}}` |
| StepRequest | `Array`, one entry per environment: `{agent_id: <point>}` |
| TrainingState | `Array`, one entry per environment: `{agent_id: {"observation": <point>, "reward": float, "terminated": bool, "truncated": bool, "info": {String: String}}}` |

### 4.6 gRPC transport and training extension: `src/transport/grpc/`, `src/training/` (US3)

```cpp
namespace schola {

struct GrpcConnectorSettings {
	std::string address = "127.0.0.1"; // Same default as the Unreal plugin; from schola/training/address.
	int32_t port = 8000;               // Same default as the Unreal plugin; overridden by -ScholaPort=<n>.
};

// Serves Schola's GymService (Proto/GymConnector.proto). gRPC threads queue incoming messages;
// wait_for_update() takes them on the main thread, as the development contract requires.
class GrpcConnector final : public Connector {
public:
	explicit GrpcConnector(GrpcConnectorSettings p_settings);
	Status open(const TrainingDefinition &p_definition) override;
	Status wait_for_start(StartRequest &r_request, std::chrono::milliseconds p_timeout) override;
	Status wait_for_update(ConnectorUpdate &r_update, std::chrono::milliseconds p_timeout) override;
	Status reply(const TrainingState *p_state, const InitialState *p_initial_state) override;
	void close() override;
};

// Training extension proxy: implements TrainingBackend by calling ScholaTrainingHost's bound methods
// with the Variant formats from 4.5.
class HostTrainingBackend final : public TrainingBackend {
public:
	explicit HostTrainingBackend(godot::Object *p_host); // Non-owning; the host is the connector node's parent.
	Status define(TrainingDefinition &r_definition) override;
	Status set_autoreset_mode(AutoResetMode p_mode) override;
	Status reset(const ResetRequest &p_request, InitialState &r_initial_state) override;
	Status step(const StepRequest &p_request, TrainingState &r_state, InitialState &r_initial_state) override;
};

} // namespace schola
```

`transport/grpc/training_messages.h` converts the training messages, using the conversions from [3.6](#36-protobuf-form-transportprotoproto_conversionh-us2) for the values inside them:

```cpp
namespace schola {

void to_proto(const TrainingDefinition &p_definition, ::Schola::TrainingDefinition &r_message);
Status from_proto(const ::Schola::GymConnectorStartRequest &p_message, StartRequest &r_request);
Status from_proto(const ::Schola::StateUpdate &p_message, const TrainingDefinition &p_definition, ConnectorUpdate &r_update); // Status CLOSED becomes UpdateKind::CLOSE; status ERROR returns CLOSED with Python's report.
void to_proto(const TrainingState *p_state, const InitialState *p_initial_state, ::Schola::State &r_message);                 // nullptr leaves that oneof unset.

} // namespace schola
```

```gdscript
class_name ScholaTrainingConnector extends Node   # Training extension. Created by ScholaTrainingHost, never placed in scenes.
var port: int                                     # -ScholaPort=<n>, otherwise schola/training/port.
var start_timeout_sec: float                      # schola/training/start_timeout_sec.
var step_timeout_sec: float                       # schola/training/step_timeout_sec.
signal training_finished(error: String)           # Empty when Python closed the connection normally.
```

The connector is created by code and never placed in a scene, so its properties cannot be edited in the Inspector. It reads them from the [project settings](#project-settings) when created. `_ready()` calls `ConnectorLoop::start`.

#### Headless and windowed training

Each Python step corresponds to exactly one physics frame in both modes. The mode is chosen automatically:

| Mode | When | Each physics frame | Why |
| --- | --- | --- | --- |
| Headless | `DisplayServer.get_name()` is `"headless"`, e.g. a game launched by Python with `--headless` | `ConnectorLoop::tick` blocks until Python's next message | Fastest; there is no window to keep responsive. This is how the Unreal plugin works. |
| Windowed | Any other display, e.g. running from the editor with `schola/training/listen_in_editor` | `ConnectorLoop::poll_tick` returns at once. While no message has arrived, the connector pauses the scene tree (`get_tree().paused`), so physics and game logic do not advance; when a message arrives, it unpauses and handles it. | Blocking would freeze the game window whenever Python is slow, for example during a PPO update that sends no steps for several seconds, and Windows would report the game as "Not Responding". Pausing keeps the window drawing. |

In windowed mode the connector uses `process_mode = PROCESS_MODE_ALWAYS` so it keeps running while the tree is paused, and `step_timeout_sec` is measured in real time.

Training never hangs silently. It ends in one of these ways:

| Situation | Detected by | Result |
| --- | --- | --- |
| Python closes normally | `StateUpdate.status` is `CLOSED` | `training_finished("")` |
| Python reports an error | `StateUpdate.status` is `ERROR` | `training_finished` with Python's report |
| Python never connects | No `StartGymConnector` within `start_timeout_sec` | `TIMEOUT`, e.g. "Python did not start training on port 8000 within 45 s. Check that the training script is running and uses the same port." |
| Python stops responding or crashes | No `UpdateState` within `step_timeout_sec` | `TIMEOUT`, e.g. "No message from Python for 60 s; the training process may have stopped. Increase `step_timeout_sec` if steps are expected to take longer." |

The protocol has no separate signal for a crashed client, so a crash is detected through the step timeout. Errors are reported once with `push_error`. The connector then closes. If Python launched the game (`-ScholaPort` was given), the game quits with exit code 0 after a normal close and 1 after an error, so no headless process is left running.

#### Python launcher: `schola/core/simulators/godot/executable_simulator.py` (US3)

A new simulator, alongside `UnrealExecutable`, with the same parameters so Schola users already know them. It is the only Python change, reuses the existing gRPC protocol unchanged, and needs AMD's agreement.

```python
class GodotExecutable(BaseSimulator):
    def __init__(
        self,
        executable_path: str | Path,          # Exported game, or the Godot binary with "--path <project>" in extra_args.
        headless_mode: bool = False,          # --headless: no window and no rendering.
        scene: str | None = None,             # -ScholaScene=<res://path.tscn>; replaces UnrealExecutable's `map`.
        display_logs: bool = True,            # Forward the game's output to the Python console.
        set_fps: int | None = None,           # --fixed-fps <n>: fixed time step, as fast as possible (Unreal: -BENCHMARK -FPS=<n>).
        extra_args: list[str] | None = None,  # Appended before "--".
        validate_path: bool = True,           # Fail early if executable_path does not exist.
    ): ...
```

Command line: `<executable> [--headless] [--fixed-fps <n>] [extra_args] -- -ScholaPort=<port> [-ScholaScene=<scene>]`

Behaviour verified with Godot 4.7.2 exports:

- Schola's arguments must follow `--`. They then appear in `OS.get_cmdline_user_args()`; without `--` they do not.
- Exported games, both release and debug, reject a scene path on the command line ("compiled without support for path overrides"). The scene is therefore passed as `-ScholaScene` and loaded by `ScholaTrainingHost`.
- `--fixed-fps 60` keeps the physics time step at 1/60 s but stops waiting for real time. An empty headless scene ran 121 physics frames in 2 s without it and over 500,000 with it. Without `set_fps`, training runs at real-time speed.

### 4.7 Policy and inference: `src/core/policy/`, `src/inference/`, `src/bindings/inference/` (US7)

`core/policy/policy.h` (Unreal: `IPolicy`):

A policy serves a fixed number of agents. Each agent has an index from 0 to `agent_count - 1`, so a recurrent policy can keep separate memory per agent and clear it when that agent's episode ends.

```cpp
namespace schola {

class Policy {
public:
	virtual ~Policy() = default;
	virtual Status init(const InteractionDefinition &p_definition, int32_t p_agent_count) = 0; // Checks the policy can serve the definition's spaces; INCOMPATIBLE lists every mismatch. Allocates per-agent memory.
	virtual Status think(int32_t p_agent, const Point &p_observation, Point &r_action) = 0;                         // One action for agent p_agent; r_action comes from action_space.make_point().
	virtual Status batched_think(const std::vector<const Point *> &p_observations, const std::vector<Point *> &r_actions); // Entry i belongs to agent i; one entry per agent. Default calls think() for each agent.
	virtual void reset(int32_t p_agent) {}                                                                          // Clears the memory of one agent at the start of its episode. Stateless policies ignore it.
	virtual void reset_all() {}                                                                                     // Clears the memory of every agent.
	virtual bool is_recurrent() const { return false; }                                                             // True if the policy keeps memory between calls.
	virtual bool is_busy() const { return false; }                                                                  // True while an asynchronous inference runs.
};

} // namespace schola
```

`core/policy/simple_stepper.h` (Unreal: `USimpleStepper`):

```cpp
namespace schola {

class SimpleStepper {
public:
	Status init(const std::vector<Agent *> &p_agents, Policy *p_policy); // Non-owning. Agents must declare identical spaces; calls Policy::init with the first agent's InteractionDefinition (from Agent::define) and the agent count. Agent i keeps index i.
	Status step();                                                       // Observes every agent, runs one batched_think, applies every action.
	void reset(int32_t p_agent);                                         // Forwards to Policy::reset at the start of one agent's episode.
	void reset_all();                                                    // Forwards to Policy::reset_all.
};

} // namespace schola
```

`inference/onnx_policy.h` (Unreal: `UNNEPolicy`):

```cpp
namespace schola {

class OnnxPolicy final : public Policy {
public:
	Status load_model(const uint8_t *p_data, size_t p_size, const std::string &p_model_name); // Parses an ONNX file from memory; INVALID_DATA if corrupt; INCOMPATIBLE if its recurrent state breaks the rules in 4.8.
	Status init(const InteractionDefinition &p_definition, int32_t p_agent_count) override;
	Status think(int32_t p_agent, const Point &p_observation, Point &r_action) override;
	Status batched_think(const std::vector<const Point *> &p_observations, const std::vector<Point *> &r_actions) override; // One model run for all agents, including their memory.
	void reset(int32_t p_agent) override;                                                      // Sets the agent's memory back to zeros.
	void reset_all() override;
	bool is_recurrent() const override;                                                        // True if the model has state_in/state_out tensors (4.8).
	bool is_ready() const;                                                                     // True after load_model() and init() succeed.
};

} // namespace schola
```

```gdscript
class_name ScholaOnnxPolicy extends Resource
@export_file("*.onnx") var model_path: String
func load() -> Error                               # Reads the file through FileAccess (works in exported .pck files).
func is_loaded() -> bool
func is_recurrent() -> bool                        # True if the model keeps memory between inferences (4.8).
func get_last_error() -> String                    # Full diagnostic of the last failure; empty on success.
func get_input_names() -> PackedStringArray
func get_output_names() -> PackedStringArray
func infer(observation: Variant, agent: int = 0) -> Variant # One inference on a GDScript value (3.5); for custom loops and tests. agent selects whose memory is used.
func reset_memory(agent: int) -> void              # Clears one agent's memory used by infer().
func reset_all_memory() -> void                    # Clears every agent's memory used by infer().

class_name ScholaInferenceStepper extends Node
@export var policy: ScholaOnnxPolicy
@export var agents: Array[NodePath]                # ScholaAgent nodes sharing this policy; position in the array is the agent index.
@export var enabled: bool = true
func step() -> bool                                # One observe, think, act cycle; called every physics frame when enabled.
func reset(agent: ScholaAgent) -> void             # Call when this agent's episode starts; clears its memory.
func reset_all() -> void                           # Call when every agent's episode starts.
func _get_configuration_warnings() -> PackedStringArray # Editor warning icon; returns get_configuration_errors().
signal inference_failed(message: String)
```

```cpp
godot::PackedStringArray ScholaInferenceStepper::get_configuration_errors() const; // Configuration problems of this node; empty when valid.
std::unique_ptr<schola::OnnxPolicy> ScholaOnnxPolicy::instantiate() const;         // New policy with its own memory; the loaded model is shared, not loaded again.
```

Memory belongs to a policy instance, not to the resource. Each `ScholaInferenceStepper` calls `instantiate()` once, so two steppers that share one `ScholaOnnxPolicy` resource never share memory. `infer()` uses the resource's own instance.

`ScholaInferenceStepper` follows the configuration checks in [4.4](#configuration-checks). It reports:

| Problem reported |
| --- |
| `policy` is not set, or its `model_path` is empty. |
| `agents` is empty. |
| A path in `agents` does not point to a `ScholaAgent`. |
| The agents declare different observation or action spaces. |

Whether the model matches the agents' spaces is checked when the scene runs, by `Policy::init`, because it requires loading the model.

Inference does not reset environments; as in the Unreal plugin, the game decides when an episode restarts.

### 4.8 ONNX model contract (US7)

Models exported by Schola's existing Python tools (`schola sb3 export`, `schola rllib export`) follow these conventions, which US7 validates on load:

| Space | Observation input | Action output |
| --- | --- | --- |
| Box(shape, dtype) | `dtype` `[batch, *shape]`, e.g. uint8, int32, double | float32 `[batch, *shape]` for float32 action spaces |
| Discrete(n) | int64 `[batch]` | int64 `[batch]` |
| MultiDiscrete(nvec) | int64 `[batch, len(nvec)]` | int64 `[batch, len(nvec)]` |
| MultiBinary(n) | int8 `[batch, n]` | bool `[batch, n]` |

A non-Dict observation space is the input `obs`; a non-Dict action space is the output `action`; Dict spaces use one tensor per key. Verified by exporting one model per space type with `schola.sb3.export`, including Box observations of type uint8, int32, and float64, whose inputs have that type. US7 therefore converts the float values of a `BoxPoint` to the model's declared input type.

#### Recurrent state

Recurrent policies, such as LSTMs, remember earlier steps. Schola's exporter (`Resources/python/schola/core/model.py`) gives such a model extra tensors, which `OnnxPolicy` supports:

| Tensor | Name | Shape | Meaning |
| --- | --- | --- | --- |
| State input | `state_in/<key>` | `[batch, *state]`, or `[batch, seq_len, *state]` with a sequence dimension | The memory fed into this step |
| State output | `state_out/<key>` | `[batch, *state]` | The new memory produced by this step |

Rules:

- **Recognition.** A tensor is recurrent state only if its name starts with `state_in/` or `state_out/`, the prefixes Unreal's `NNEPolicy` also uses. Any other input that matches no observation key is a mismatch and fails with `INCOMPATIBLE`; it is never treated as memory.
- **Pairing.** Each `state_in/<key>` must have a `state_out/<key>` with the same key and matching state shape, and the reverse. A missing partner fails `load_model()` with `INCOMPATIBLE`. Unreal pairs them by position; matching by key is stricter.
- **Element type.** State tensors are float32; any other type fails with `INCOMPATIBLE`.
- **Metadata.** The exporter stores each state input's `StateMetadata` in that input's ONNX `metadata_props`: `has_seq_dim` (`"True"` or `"False"`), and, when it is true, `seq_dim` and `max_seq_len`. `OnnxPolicy` reads it on load. A sequence dimension must be dimension 1, directly after the batch dimension. Missing metadata means no sequence dimension. Metadata with `has_seq_dim` true but no valid `seq_dim` or `max_seq_len`, or a `seq_dim` other than 1, fails with `INCOMPATIBLE`. Unreal ignores this metadata and uses a user setting instead; the Godot port uses the length the exporter recorded.
- **Memory per agent.** Each agent index has its own memory for every state tensor. `batched_think()` stacks the agents' memories along the batch dimension and splits the new memories back after the run.
- **Without a sequence dimension.** After each step, the agent's memory is replaced by its `state_out`.
- **With a sequence dimension.** The memory is a window of the last `max_seq_len` states, oldest first, passed as `state_in`. After each step, the oldest state is dropped and `state_out` is appended as the newest, as in Unreal's `FNNEStateBuffer`.
- **Start and reset.** Memory starts as zeros, as in Unreal, and `reset(agent)` sets it back to zeros. Unreal's `IPolicy` has no reset, so its memory carries over between episodes; the Godot port clears it.
- **Verification.** Tests compare `OnnxPolicy` against Python `onnxruntime` over several consecutive steps of a recurrent model exported by Schola, including after a reset.

### 4.9 Test doubles: `tests/unit/support/`, `tests/integration/support/` (all stories)

Hand-written fakes let each story be tested without the others' implementations. The development contract allows no new test framework, so no mocking library is used. Each interface owner writes and maintains the fake for their interface. C++ fakes live in `tests/unit/support/`, which the existing `unit_tests` target already compiles. GDScript fakes live in `tests/integration/support/`.

Every fake follows the same pattern: public fields script what it returns, public fields record what it received, and `next_error` makes the next call fail once, to test error paths.

```cpp
namespace schola::testing {

class FakeEnvironment final : public Environment { // US1
public:
	std::map<AgentId, InteractionDefinition> agents; // Returned by initialize().
	int32_t episode_length = 10;                     // Every agent terminates after this many steps.
	float reward = 1.0f;                             // Reward for every agent on every step.
	std::vector<ResetSettings> resets;               // Every reset() call, in order.
	std::vector<std::map<AgentId, Point>> steps;     // Actions received by every step() call, in order.
	Status next_error = Status::ok();                // Returned once by the next call.
	// Observations are zero-filled points of each agent's observation space.
};

class FakeAgent final : public Agent { // US1
public:
	InteractionDefinition definition; // Returned by define().
	Point observation;                // Returned by every observe().
	std::vector<Point> actions;       // Every act() call, in order.
	Status next_error = Status::ok();
};

class FakeConnector final : public Connector { // US3
public:
	StartRequest start_request;                // Returned by wait_for_start().
	std::deque<ConnectorUpdate> updates;       // wait_for_update() pops the next one, TIMEOUT when empty; poll_update() pops the next one, NOT_FOUND when empty.
	std::optional<TrainingDefinition> opened;  // Definition passed to open().
	std::vector<TrainingState> state_replies;  // Every non-null p_state passed to reply().
	std::vector<InitialState> initial_replies; // Every non-null p_initial_state passed to reply().
	bool closed = false;                       // Set by close().
	Status next_error = Status::ok();
};

class FakeTrainingBackend final : public TrainingBackend { // US4
public:
	TrainingDefinition definition;     // Returned by define().
	std::optional<AutoResetMode> mode; // Set by set_autoreset_mode().
	std::vector<ResetRequest> resets;  // Every reset() call, in order.
	std::vector<StepRequest> steps;    // Every step() call, in order.
	Status next_error = Status::ok();
	// reset() and step() return zero-filled observations for every agent in the definition.
};

class FakePolicy final : public Policy { // US7
public:
	Point action;                    // Copied into r_action by every think().
	std::vector<int32_t> agents;     // Agent index of every observation received, in order.
	std::vector<Point> observations; // Every observation received, in order.
	std::vector<int32_t> resets;     // Agent index of every reset() call; reset_all() records -1.
	Status next_error = Status::ok();
};

} // namespace schola::testing
```

GDScript fakes for GdUnit4 tests (US1):

| File | Behaviour |
| --- | --- |
| `fake_agent.gd` (extends `ScholaAgent`) | `_observe()` returns `observation_value`; `_act()` appends to `received_actions`. |
| `fake_environment.gd` (extends `ScholaEnvironment`) | `_get_reward()` returns `reward_value`; `_is_terminated()` becomes true after `episode_length` steps; `_reset_episode()` appends the seed to `received_seeds`. |

### 4.10 Editor plugin and project settings: `addons/schola/`, `src/interop/`, `src/bindings/` (US5)

#### Editor plugin

The plugin's only job is to install the training host autoload. It is written in GDScript because Godot calls `_enable_plugin()` and `_disable_plugin()` only for plugins declared in a `plugin.cfg`; an editor plugin registered from C++ is always active and receives no such calls.

`addons/schola/plugin.cfg`:

```ini
[plugin]
name="Schola"
description="Reinforcement learning with AMD Schola."
author="AMD"
version="0.1.0"
script="plugin.gd"
```

`addons/schola/plugin.gd`:

```gdscript
@tool
extends EditorPlugin

const AUTOLOAD_NAME := "ScholaTrainingHost"
const AUTOLOAD_PATH := "res://addons/schola/training_host.tscn" # Scene whose root is a ScholaTrainingHost node.

func _enable_plugin() -> void   # Adds the autoload with add_autoload_singleton(), unless it already exists.
func _disable_plugin() -> void  # Removes the autoload with remove_autoload_singleton().
```

Rules:

- Node icons are declared in the `[icons]` section of `schola.gdextension`, so they do not depend on the plugin being enabled.
- Project settings are registered by the runtime extension, not by the plugin (see below), so they exist even when the plugin is disabled and in exported games.
- If the plugin is not enabled, training cannot start because the `ScholaTrainingHost` autoload is absent. The training-startup path reports this only when training is requested: `The Schola plugin is not enabled, so training cannot start. Enable it in Project Settings > Plugins.` It checks for the project setting `autoload/ScholaTrainingHost`. `ScholaEnvironment` itself does not report this as a configuration error, so inference-only and exported projects remain valid without the training add-on.

#### Project settings

All Schola settings are listed here. They appear in **Project Settings** under **Schola**.

| Setting | Type | Default | Read by | Purpose |
| --- | --- | --- | --- | --- |
| `schola/training/listen_in_editor` | `bool` | `false` | `ScholaTrainingHost` | Start training when the game is run from the editor (feature tag `editor`), without `-ScholaPort`. Python then connects to the running game, for example with its existing `ExternalSimulator`. Ignored in exported games, so a shipped game never listens unless Python launches it. |
| `schola/training/address` | `String` | `"127.0.0.1"` | `ScholaTrainingConnector` | Address the gRPC server listens on. Use `0.0.0.0` to accept connections from other machines, for example in the Docker cluster setup. |
| `schola/training/port` | `int` (1–65535) | `8000` | `ScholaTrainingConnector` | Port when `-ScholaPort` is not given. `-ScholaPort` always takes precedence. |
| `schola/training/start_timeout_sec` | `float` (≥ 0) | `45.0` | `ScholaTrainingConnector` | Time to wait for Python to start training; matches Python's default `environment_start_timeout`. 0 waits indefinitely. |
| `schola/training/step_timeout_sec` | `float` (≥ 0) | `60.0` | `ScholaTrainingConnector` | Time to wait for each message from Python (4.6). 0 waits indefinitely and is intended only for debugging. |
| `schola/validation/strict_bounds` | `bool` | `false` | `ScholaTrainingHost`, `ScholaAgent` adapter | Turn Box bounds warnings into errors ([validation](#validation-of-actions-and-observations)). |

Names and defaults are defined once and shared by both extensions. `src/interop/project_settings.h`:

```cpp
namespace schola::settings {

constexpr const char *TRAINING_LISTEN_IN_EDITOR = "schola/training/listen_in_editor";
constexpr const char *TRAINING_ADDRESS = "schola/training/address";
constexpr const char *TRAINING_PORT = "schola/training/port";
constexpr const char *TRAINING_START_TIMEOUT_SEC = "schola/training/start_timeout_sec";
constexpr const char *TRAINING_STEP_TIMEOUT_SEC = "schola/training/step_timeout_sec";
constexpr const char *VALIDATION_STRICT_BOUNDS = "schola/validation/strict_bounds";

godot::Variant get(const char *p_name); // Current value, or the default from the table above if the project does not set it.

} // namespace schola::settings
```

Registration, in the runtime extension only (`src/bindings/project_settings.h`, called from the bindings registration hook):

```cpp
void register_schola_project_settings(); // Adds every setting above with its default, type, and range, so it appears in Project Settings. Existing values are kept.
```

The training extension never registers settings; it only reads them through `schola::settings::get()`. Because the runtime extension is always present, the settings exist in every project that uses Schola.

## 5. One step, call by call

### 5.1 Training startup

1. Python's `GodotExecutable` launches the game with `-- -ScholaPort=<n>` (see [4.6](#python-launcher-scholacoresimulatorsgodotexecutable_simulatorpy-us3)).
2. `ScholaTrainingHost._ready()` finds the `ScholaTrainingConnector` class and creates the connector node.
3. `ScholaTrainingConnector._ready()` calls `ConnectorLoop::start`: `HostTrainingBackend::define` calls `ScholaTrainingHost.define()`, which calls `EnvironmentRunner::define`, which calls `Environment::initialize` on every environment.
4. `GrpcConnector::open` serves the definition. Python calls `RequestTrainingDefinition`, then `StartGymConnector`.
5. `wait_for_start` returns the auto-reset mode; `set_autoreset_mode` forwards it to the runner.

### 5.2 Training step (main thread, once per physics frame)

1. `ScholaTrainingConnector._physics_process` calls `ConnectorLoop::tick`.
2. `GrpcConnector::wait_for_update` blocks until a gRPC thread queues Python's `UpdateState` message, then converts it to a `ConnectorUpdate`.
3. For a step: `HostTrainingBackend::step` calls `ScholaTrainingHost.step(actions)`, which calls `EnvironmentRunner::step`, which calls `Environment::step` on each environment: `_act` on each agent, then `_observe`, `_get_reward`, `_is_terminated`, `_is_truncated`, `_get_info`.
4. The runner applies auto-reset; the host returns the state; `GrpcConnector::reply` sends it to Python.
5. Godot runs physics for the frame. The next action from Python arrives on the next frame.

### 5.3 Inference step (main thread, once per physics frame)

1. `ScholaInferenceStepper._physics_process` calls `SimpleStepper::step`.
2. `Agent::observe` is called for every agent, which calls `ScholaAgent._observe()`.
3. `OnnxPolicy::batched_think` runs the model once for all agents. For a recurrent model, each agent's memory goes in as `state_in` and is replaced by its `state_out`.
4. `Agent::act` is called for every agent, which calls `ScholaAgent._act(action)`.
5. When an agent's episode restarts, the game calls `ScholaInferenceStepper.reset(agent)`, which clears that agent's memory.

## 6. Compatibility with existing Schola

| Core type | Protobuf message | Unreal type |
| --- | --- | --- |
| `BoxSpace` | `BoxSpace` (`dimensions`, `shape_dimensions`) | `FBoxSpace` |
| `DiscreteSpace::n` | `DiscreteSpace.high` | `FDiscreteSpace::High` |
| `MultiDiscreteSpace::nvec` | `MultiDiscreteSpace.high` | `FMultiDiscreteSpace` |
| `MultiBinarySpace::n` | `MultiBinarySpace.shape` | `FMultiBinarySpace` |
| `DictSpace` | `DictSpace.spaces` | `FDictSpace` |
| `Point` kinds | `Point` oneof | `FBoxPoint`, `FDiscretePoint`, ... |
| `InteractionDefinition` | `AgentDefinition` | `FInteractionDefinition` |
| `TrainingDefinition` | `TrainingDefinition` | `FTrainingDefinition` |
| `AgentState` | `AgentState` | `FAgentState` |
| `InitialAgentState` | `InitialAgentState` | `FInitialAgentState` |
| `ResetSettings` | `EnvironmentSettings` | `FEnvReset` |
| `StepRequest` | `Step` | `FTrainingStep` |
| `ResetRequest` | `Reset` | `FTrainingReset` |
| `TrainingState` | `TrainingState` | `FTrainingState` |
| `InitialState` | `InitialState` | `FInitialState` |
| `AutoResetMode` | `AutoResetType` | `EAutoResetType` |

Conversion between core types and protobuf lives only in the training extension: `transport/proto` (US2) converts spaces, points, interaction definitions, and agent states; `transport/grpc` (US3) converts training messages.

## 7. Open decisions

| # | Decision | Proposal | Needs agreement from |
| --- | --- | --- | --- |
| 1 | Shared error type | `Status` in 3.1 | All stories |
| 2 | Step timing | One Python step per physics frame; `step()` applies actions and observes in the same call, as in Unreal | US1, US3, US4 |
| 3 | Training startup | `ScholaTrainingHost` autoload, added by the add-on's editor plugin, creates `ScholaTrainingConnector` by class name and loads `-ScholaScene` if given (4.5) | US3, US4, US5 |
| 4 | `src/interop` compiled into both extensions | Separate `SConstruct` pull request | Foundation maintainer |
| 5 | Python `GodotExecutable` simulator | Only Python change; reuses the protocol | US3, AMD |
| 6 | Clipping Box actions to bounds | No, matching the Python exporter. Out-of-bounds actions are reported by bounds validation instead (decision 11) | AMD |
| 7 | Inference episode resets | The game decides, as in Unreal | US5, US7 |
| 8 | Text spaces | Not in the MVP | US2, AMD |
| 9 | Step timeout | 60 s default (`step_timeout_sec`); Python's `CLOSED` or `ERROR` status ends training immediately; 0 disables the timeout for debugging | US3 |
| 10 | Box data types | Every `DType` from `Proto/DType.proto`; values stay float because `BoxPoint.values` is a float list, so large integers and 64-bit values lose precision (3.3) | US2, AMD |
| 11 | Validation of actions and observations | Structural mismatches always fail; Box values outside bounds produce a warning unless `schola/validation/strict_bounds` is enabled (4.2) | US2, US4 |
| 12 | Seeding | `ScholaEnvironment.get_rng()` per environment; a seed re-seeds it, a reset without a seed continues the stream, as in Gymnasium (4.4) | US1 |
| 13 | Test doubles | Hand-written fakes; each interface owner writes the fake for their interface (4.9) | All stories |
| 14 | Python launcher arguments | `GodotExecutable` passes `--fixed-fps <n>` for training speed and `-ScholaScene` after `--`, because exported games reject scene paths on the command line (4.6) | US3, AMD |
| 15 | Recurrent policies | Supported: `state_in/*` and `state_out/*` tensors, per-agent memory cleared on reset, sequence windows from the exporter's metadata (4.8). The policy API takes an agent index for this (4.7) | US7 |
| 16 | Waiting for Python | Block in headless mode; in windowed mode poll with `Connector::poll_update` and pause the scene tree until a message arrives, so the window stays responsive (4.6) | US3 |
