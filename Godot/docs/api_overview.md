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
| `src/bindings/environment/` | Environment and agent nodes shown in the editor | US5 | Yes | `schola` | `core`, `interop` |
| `src/bindings/lifecycle/` | `ScholaTrainingHost`: runs the environment lifecycle for the training extension | US4 | Yes | `schola` | `core`, `interop`, `bindings/environment` |
| `src/bindings/spaces/` | Inspector resources for declaring spaces | US2, with US5 | Yes | `schola` | `core/spaces`, `interop` |
| `src/bindings/inference/` | Policy resource and inference stepper node | US7 | Yes | `schola` | `core`, `interop`, `inference`, `bindings/environment` |
| `src/transport/grpc/` | gRPC implementation of the connector interface and protobuf conversion | US3 | No | `schola_training` | `core`, `generated/proto`, gRPC, protobuf |
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
| `ScholaProtobuf` | gRPC connector, protobuf conversion | `transport/grpc`, `generated/proto` |

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
using Info = std::map<std::string, std::string>; // Free-form per-agent data, delivered to Python's `info` dict.

} // namespace schola
```

Users: US1, US3, US4.

### 3.3 Spaces: `core/spaces/space.h` (US2)

A space describes the shape and valid range of observations or actions. `Space` is a value type: copying it copies the definition.

```cpp
namespace schola {

enum class SpaceKind { BOX, DISCRETE, MULTI_DISCRETE, MULTI_BINARY, DICT };

struct BoxSpace {
	std::vector<float> low;     // Lower bound per element, row-major; -INFINITY means unbounded.
	std::vector<float> high;    // Upper bound per element; +INFINITY means unbounded.
	std::vector<int32_t> shape; // Dimensions, e.g. {4} or {3, 64, 64}; their product equals low.size().
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

	Status check_definition() const;              // OK, or why the definition is invalid: low > high, size/shape mismatch, n <= 0, duplicate Dict key.
	Status validate(const Point &p_point) const;  // OK, or why the point does not belong: wrong kind, wrong size, or out of bounds.
	Point make_point() const;                     // Zero-filled point of this kind and size; allocate once and reuse every step.
	int64_t get_flattened_size() const;           // Number of scalars; Discrete counts 1, Dict sums its entries.
	std::string to_string() const;                // Short description for diagnostics, e.g. "Box(shape=[4], low=-1, high=1)".
};

} // namespace schola
```

Users: every story. Text spaces from `Spaces.proto` are not supported in the MVP; the Unreal plugin's ONNX inference does not support them either.

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
| Box | `PackedFloat32Array` (row-major) | `PackedFloat32Array([0.1, -0.5, 0.0, 1.0])` |
| Discrete | `int` | `2` |
| MultiDiscrete | `PackedInt32Array` | `PackedInt32Array([1, 0, 3])` |
| MultiBinary | `PackedByteArray` (each 0 or 1) | `PackedByteArray([1, 0, 1])` |
| Dict | `Dictionary` (String to value) | `{"position": PackedFloat32Array([...]), "mode": 1}` |

Across the extension boundary, spaces travel as dictionaries:

| Space kind | Dictionary |
| --- | --- |
| Box | `{"kind": "box", "low": PackedFloat32Array, "high": PackedFloat32Array, "shape": PackedInt32Array}` (`INF` and `-INF` for unbounded) |
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
	Point observation; // First observation of the episode.
	Info info;
};

struct AgentState {
	Point observation;       // Observation after the actions were applied.
	float reward = 0.0f;     // Reward for this step.
	bool terminated = false; // The episode ended for this agent, e.g. goal reached or failure.
	bool truncated = false;  // The episode was cut short, e.g. a time limit.
	Info info;
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
	virtual Status wait_for_update(ConnectorUpdate &r_update, std::chrono::milliseconds p_timeout) = 0; // Blocks the main thread until Python's next message; zero timeout waits indefinitely.
	virtual Status reply(const TrainingState *p_state, const InitialState *p_initial_state) = 0;       // Answers the last update; nullptr leaves that field unset.
	virtual void close() = 0;                                                                          // Stops listening and joins worker threads; safe to call twice.
};

// The README's engine-independent connector loop.
class ConnectorLoop {
public:
	Status start(Connector &p_connector, TrainingBackend &p_backend, std::chrono::milliseconds p_start_timeout); // define, open, wait_for_start, then set_autoreset_mode.
	Status tick(std::chrono::milliseconds p_update_timeout);                                                     // One physics frame: wait for an update, run it on the backend, reply. CLOSED when Python disconnects.
	void stop();                                                                                                 // Closes the connector.
};

} // namespace schola
```

Replies: after a reset, only `p_initial_state`; after a step, `p_state`, plus `p_initial_state` when environments were auto-reset in `SAME_STEP` mode.

### 4.4 Environment nodes and space resources: `src/bindings/environment/` (US5), `src/bindings/spaces/` (US2)

Users build environments from nodes and override virtual methods in GDScript (godot-cpp `GDVIRTUAL`). An environment's agents are its `ScholaAgent` descendants.

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
signal episode_started
signal episode_ended

class_name ScholaAgent extends Node
@export var agent_id: String = ""            # Empty means the node name. Unique within the environment.
@export var agent_type: String = ""          # See InteractionDefinition::agent_type.
@export var observation_space: ScholaSpace
@export var action_space: ScholaSpace
func _observe() -> Variant                   # Virtual. Returns a value in the GDScript form of the observation space (3.5).
func _act(action: Variant) -> void           # Virtual. Receives a value in the GDScript form of the action space.
```

C++ accessors used by other runtime modules (same extension, so direct calls are safe):

```cpp
schola::Environment *ScholaEnvironment::get_environment(); // Core adapter over this node; valid while the node is in the tree.
schola::Agent *ScholaAgent::get_agent();                   // Core adapter over this node; valid while the node is in the tree.
```

`ScholaEnvironment::step()` calls `_act` on every agent with an action, then `_observe`, `_get_reward`, `_is_terminated`, `_is_truncated`, and `_get_info` on each of them. Invalid return values are reported once with `push_error` and fail the step with `INVALID_ARGUMENT`.

Space resources, edited in the Inspector:

```gdscript
class_name ScholaSpace extends Resource                    # Abstract base.
func get_validation_error(value: Variant) -> String        # Empty if value belongs to the space; otherwise why not.

class_name ScholaBoxSpace extends ScholaSpace
@export var low: PackedFloat32Array
@export var high: PackedFloat32Array
@export var shape: PackedInt32Array                          # Empty means [low.size()].

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

### 4.5 Training host: `src/bindings/lifecycle/` (US4)

`ScholaTrainingHost` is the single runtime object the training extension talks to. `addons/schola/` contains a small scene whose root is a `ScholaTrainingHost` node, and the add-on's editor plugin adds that scene as an autoload when the plugin is enabled. The host is harmless in shipped games: without the training extension it does nothing.

```gdscript
class_name ScholaTrainingHost extends Node
func define() -> Dictionary                        # {"error": String, "definition": <TrainingDefinition>}
func set_autoreset_mode(mode: int) -> Dictionary   # mode: 0 SAME_STEP, 1 NEXT_STEP, 2 DISABLED. Returns {"error": String}.
func reset(request: Dictionary) -> Dictionary      # <ResetRequest> to {"error": String, "initial_state": <InitialState>}
func step(actions: Array) -> Dictionary            # <StepRequest> to {"error": String, "state": <TrainingState>, "initial_state": <InitialState>}
```

`"error"` is empty on success. `define()` collects every `ScholaEnvironment` in the current scene in scene-tree order; that order is the `EnvironmentId`.

Startup: in `_ready()`, if `ClassDB.class_exists("ScholaTrainingConnector")` and training is requested (`-ScholaPort=<n>` on the command line, or the project setting `schola/training/listen_in_editor`), the host instantiates `ScholaTrainingConnector` by class name and adds it as a child. Otherwise it does nothing. This keeps the runtime free of compile-time dependencies on training code.

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
	std::string address = "127.0.0.1"; // Same default as the Unreal plugin.
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

```gdscript
class_name ScholaTrainingConnector extends Node   # Training extension. Created by ScholaTrainingHost, never placed in scenes.
@export var port: int = 8000                      # -ScholaPort=<n>, then schola/training/port, then 8000.
@export var start_timeout_sec: float = 45.0       # Matches Python's default environment_start_timeout.
@export var step_timeout_sec: float = 0.0         # 0 waits indefinitely.
signal training_finished(error: String)           # Empty when Python closed the connection normally.
```

`_ready()` calls `ConnectorLoop::start`; `_physics_process()` calls `ConnectorLoop::tick`. When Python closes the connection of a game it launched, the game quits.

Python side: a `GodotExecutable` simulator, alongside `UnrealExecutable`, launches the game as `<game> --headless -- -ScholaPort=<port>` and reuses the existing gRPC protocol unchanged. This is the only Python change and needs AMD's agreement.

### 4.7 Policy and inference: `src/core/policy/`, `src/inference/`, `src/bindings/inference/` (US7)

`core/policy/policy.h` (Unreal: `IPolicy`):

```cpp
namespace schola {

class Policy {
public:
	virtual ~Policy() = default;
	virtual Status init(const Space &p_observation_space, const Space &p_action_space) = 0; // Checks the policy can serve these spaces; INCOMPATIBLE lists every mismatch.
	virtual Status think(const Point &p_observation, Point &r_action) = 0;                  // One action; r_action comes from action_space.make_point().
	virtual Status batched_think(const std::vector<const Point *> &p_observations, const std::vector<Point *> &r_actions); // Default calls think() per agent.
	virtual void reset() {}                                                                 // Clears per-episode state, e.g. recurrent memory.
	virtual bool is_busy() const { return false; }                                          // True while an asynchronous inference runs.
};

} // namespace schola
```

`core/policy/simple_stepper.h` (Unreal: `USimpleStepper`):

```cpp
namespace schola {

class SimpleStepper {
public:
	Status init(const std::vector<Agent *> &p_agents, Policy *p_policy); // Non-owning. Agents must declare identical spaces; calls Policy::init.
	Status step();                                                       // Observes every agent, runs one batched_think, applies every action.
	void reset();                                                        // Forwards to Policy::reset at an episode start.
};

} // namespace schola
```

`inference/onnx_policy.h` (Unreal: `UNNEPolicy`):

```cpp
namespace schola {

class OnnxPolicy final : public Policy {
public:
	Status load_model(const uint8_t *p_data, size_t p_size, const std::string &p_model_name); // Parses an ONNX file from memory; INVALID_DATA if corrupt.
	Status init(const Space &p_observation_space, const Space &p_action_space) override;
	Status think(const Point &p_observation, Point &r_action) override;
	Status batched_think(const std::vector<const Point *> &p_observations, const std::vector<Point *> &r_actions) override;
	bool is_ready() const;                                                                     // True after load_model() and init() succeed.
};

} // namespace schola
```

```gdscript
class_name ScholaOnnxPolicy extends Resource
@export_file("*.onnx") var model_path: String
func load() -> Error                               # Reads the file through FileAccess (works in exported .pck files).
func is_loaded() -> bool
func get_last_error() -> String                    # Full diagnostic of the last failure; empty on success.
func get_input_names() -> PackedStringArray
func get_output_names() -> PackedStringArray
func infer(observation: Variant) -> Variant        # One inference on a GDScript value (3.5); for custom loops and tests.

class_name ScholaInferenceStepper extends Node
@export var policy: ScholaOnnxPolicy
@export var agents: Array[NodePath]                # ScholaAgent nodes sharing this policy.
@export var enabled: bool = true
func step() -> bool                                # One observe, think, act cycle; called every physics frame when enabled.
func reset() -> void                               # Call at an episode start; forwards to Policy::reset.
signal inference_failed(message: String)
```

Inference does not reset environments; as in the Unreal plugin, the game decides when an episode restarts.

### 4.8 ONNX model contract (US7)

Models exported by Schola's existing Python tools (`schola sb3 export`, `schola rllib export`) follow these conventions, which US7 validates on load:

| Space | Observation input | Action output |
| --- | --- | --- |
| Box(shape) | float32 `[batch, *shape]` | float32 `[batch, *shape]` |
| Discrete(n) | int64 `[batch]` | int64 `[batch]` |
| MultiDiscrete(nvec) | int64 `[batch, len(nvec)]` | int64 `[batch, len(nvec)]` |
| MultiBinary(n) | int8 `[batch, n]` | bool `[batch, n]` |

A non-Dict observation space is the input `obs`; a non-Dict action space is the output `action`; Dict spaces use one tensor per key. Verified by exporting one model per space type with `schola.sb3.export`.

## 5. One step, call by call

### 5.1 Training startup

1. Python launches the game with `-ScholaPort=<n>`.
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
3. `OnnxPolicy::batched_think` runs the model once for all agents.
4. `Agent::act` is called for every agent, which calls `ScholaAgent._act(action)`.

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

Conversion between core types and protobuf lives only in `transport/grpc`.

## 7. Open decisions

| # | Decision | Proposal | Needs agreement from |
| --- | --- | --- | --- |
| 1 | Shared error type | `Status` in 3.1 | All stories |
| 2 | Step timing | One Python step per physics frame; `step()` applies actions and observes in the same call, as in Unreal | US1, US3, US4 |
| 3 | Training startup | `ScholaTrainingHost` autoload creates `ScholaTrainingConnector` by class name | US3, US4, US5 |
| 4 | `src/interop` compiled into both extensions | Separate `SConstruct` pull request | Foundation maintainer |
| 5 | Python `GodotExecutable` simulator | Only Python change; reuses the protocol | US3, AMD |
| 6 | Clipping Box actions to bounds | No, matching the Python exporter | AMD |
| 7 | Inference episode resets | The game decides, as in Unreal | US5, US7 |
| 8 | Text spaces | Not in the MVP | US2, AMD |
| 9 | Step timeout | Wait indefinitely by default | US3 |
