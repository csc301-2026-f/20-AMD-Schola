# Schola for Godot

This directory contains the Godot port of AMD Schola. The design keeps reusable reinforcement-learning logic independent from Godot, gRPC, and ONNX so that each part can be developed and tested separately.

Repository workflow and contribution requirements are defined in [`CONTRIBUTING.md`](../CONTRIBUTING.md). Binding engineering rules are defined in the [`Godot development contract`](docs/development_contract.md). This guide contains the supported toolchain and executable development commands.

## Supported toolchain

| Component | Initial baseline |
| --- | --- |
| Godot | 4.7.2 |
| `godot-cpp` | `10.0.0-stable` (`507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`) |
| C++ | C++17, matching `godot-cpp` |
| Python | 3.12 in CI; 3.7 or newer for SCons 4.10.1 |
| SCons | 4.10.1 |
| Primary CI | Ubuntu 22.04, x86-64, GCC |
| Local development | Linux/GCC, Windows/MSVC, and macOS/Apple Clang |

Dependency decisions are centralized in [`dependencies.lock.json`](dependencies.lock.json). `godot-cpp` and Catch2 are pinned Git submodules, and CI verifies that their checked-out commits match the lock. ONNX Runtime 1.30.0 (CPU, C API) is pinned for Windows x86_64, Linux x86_64, and macOS arm64. Microsoft's prebuilt package is downloaded and checksum-verified into the git-ignored `thirdparty/onnxruntime/` by `python Godot/tools/setup_onnxruntime.py`; it is not committed. Run the script before building. Only the runtime extension links ONNX Runtime, and the build installs its library next to `schola` so exported games include it. ONNX Runtime has no universal macOS package, so macOS builds use `arch=arm64`. The existing gRPC and Protocol Buffers files under `Source/ThirdParty/` are an Unreal-specific reference build, not an approved Godot dependency. Their Godot acquisition and compatible versions require an isolated build spike and AMD confirmation. Feature branches must not select those versions independently. Neither gRPC nor Protocol Buffers is linked into the runtime target.

Engine-independent C++ unit tests use the pinned Catch2 submodule and live under `tests/unit/`. Build and run them from the repository root with:

```sh
scons -C Godot unit_tests platform=linux target=template_debug -j"$(nproc)"
./Godot/build/tests/schola_core_tests
```

Use the matching platform value on macOS or Windows. ONNX Runtime tests live under `tests/inference/` and build as a separate target, so the core unit tests do not need ONNX Runtime:

```sh
scons -C Godot inference_tests platform=linux target=template_debug -j"$(nproc)"
./Godot/build/tests/schola_inference_tests
```

Godot scene and extension integration tests use pinned GdUnit4 and live under `tests/integration/`. Install and run the integration tests from the repository root:

```sh
python Godot/tools/setup_test_dependencies.py
godot --headless --path Godot --import
godot --headless --path Godot \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests/integration
```

Run only the training-host lifecycle suite with:

```sh
godot --headless --path Godot \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests/integration/training_host_test.gd
```

The focused suite runs against the native Godot environment adapter and covers
multiple environments, episode completion, all three autoreset modes, session
failure handling, and reset-request validation. Build both extensions before
running the suite.

CI runs the same suite headlessly against the supported Godot version.

Godot has an [upstream race](https://github.com/godotengine/godot/issues/98062) that can abort a completed headless import while editor add-ons are shutting down. If the import reaches completion and exits with status 134, rerun the import command. CI retries this step at most 3 times and still fails persistent import errors.

## Build and run

From a fresh checkout:

```sh
git submodule update --init --recursive
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --require-hashes -r Godot/requirements.txt
python Godot/tools/setup_onnxruntime.py
scons -C Godot platform=linux target=template_debug -j"$(nproc)"
godot --editor --path Godot
```

On macOS, use `platform=macos arch=arm64` and replace `$(nproc)` with `$(sysctl -n hw.logicalcpu)`. On Windows, run `scons -C Godot platform=windows target=template_debug` from a developer shell; SCons selects a safe default job count when `-j` is omitted. Windows unit tests run from `Godot\build\tests\schola_core_tests.exe`. Build products are copied into the matching `Godot/addons/*/bin/<platform>/` directory and are not committed.

The `schola` target contains the runtime extension. The `schola_training` target is a separate training extension and may depend on runtime and core code while implementing the merged transport contracts. The example project loads `examples/basic_environment/main.tscn`, which instantiates `ScholaRuntimeProbe`. The runtime and training probe nodes exist only to verify extension registration and loading; they are not production APIs for any user story.

The extension entry points are stable composition roots. Runtime bindings and inference register through their own `register_types` files, and training-only bindings register through `src/training/bindings/register_types`. Feature branches add registrations only to the hook owned by their module; they do not add production classes directly to the runtime or training composition roots.

## Inspect the Schola UI

### Agent identity

`ScholaAgent.agent_id` stores the configured Inspector value. Leave it empty to
use the agent node's name, or set it explicitly for an ID that stays the same when
the node is renamed. `get_resolved_agent_id()` returns that effective ID without
changing the saved property. Native adapters should use this method when registering
an agent; `get_agent_id()` returns the configured value and may be empty.

Use the same agent IDs when replicating an environment. Resolution uses the local
node name rather than a full scene path, UUID, or instance ID, so copying an entire
environment preserves its child agents' IDs when their names are unchanged.
Resolved IDs must be unique within each environment; matching IDs across separate
environments are intentional. Godot's sibling naming rules do not prevent equal
names in different descendant branches, so this resolver alone does not validate
environment-wide uniqueness. An empty fallback follows subsequent node renames;
use an explicit ID when that is undesirable.

`ScholaAgent.agent_type` is an optional policy-sharing label. Its configured value
is preserved by `get_agent_type()`. Use `get_resolved_agent_type()` for the effective
type: an explicit type takes precedence; an empty type falls back to the resolved
agent ID, which itself falls back to the node name. Resolution does not change the
saved properties. The integrated US1 adapter uses the resolved type when populating
`InteractionDefinition::agent_type`; this resolver does not implement policy sharing.

### Space resources and configuration warnings

Assign `ScholaSpace` resources to the agent's `observation_space` and
`action_space` fields. Both start unassigned and must be configured. The Inspector
offers Box, Discrete, MultiDiscrete, MultiBinary, and Dict resource types supplied
by US2, with inline help for their settings. Discrete and MultiBinary sizes start
at zero and require a positive value; their Inspector fields provide positive-size
range hints. Box dtype defaults to float32, and omitted bounds are unbounded.

Resources can be embedded in a scene or saved separately as `.tres` files. Shared
resources intentionally share configuration; use Godot's Make Unique operation
when an assignment needs an independent copy. The US5 owner has completed the
manual editor persistence checks.

Agent warning icons identify missing/invalid spaces and missing `_observe` or
`_act` hooks. The environment also reports missing agents, missing
`_get_step_result`, and duplicate resolved agent IDs, including the conflicting
node paths. Nested environments are searched independently, so matching agent IDs
across separate environments are allowed. `_reset_episode` is optional.

Warnings refresh when resources (including nested Dict entries) or scripts change,
and when agents are added, removed, renamed, or reparented. Script-hook diagnostics
inspect inherited script metadata; gameplay scripts do not need `@tool`.
`get_configuration_errors()` checks resources and scene configuration; the editor
adds missing-hook warnings. Runtime adapter calls still validate required hooks
before invoking them.

### Episode endings

Schola does not impose a built-in episode step limit. The environment supplies
termination and truncation results. Implement any desired time or step limit in
your environment's `_get_step_result(agent)` hook by returning `truncated: true`.

The native adapter calls `_act` for all acting agents, then `_observe` and
`_get_step_result` for each agent in scene-tree order. The result hook returns a
Dictionary with these fields:

| Field | Type | Default |
| --- | --- | --- |
| `reward` | Finite int or float within float32 range | Required |
| `terminated` | bool: natural episode ending | `false` |
| `truncated` | bool: user-defined external cutoff | `false` |
| `info` | Dictionary of String/StringName keys and values | `{}` |

Both flags may be true. Unknown fields, incorrect types, missing rewards, and
nonfinite or overflowing rewards produce an error naming the agent. Values are
not silently coerced. A missing hook is detected before any action runs. An
invalid returned result is detected after actions have run, so the caller must
end the training session; no partial result batch is published.

```gdscript
extends ScholaEnvironment

@export var episode_length: int = 200 # A setting owned by this environment.

func _reset_episode(_seed: Variant, _options: Dictionary) -> void:
    # Restore your gameplay state here. The adapter resets its step counter.
    pass

func _get_step_result(agent: ScholaAgent) -> Dictionary:
    return {
        "reward": calculate_reward(agent), # Your gameplay reward function.
        "terminated": reached_goal(agent), # Your gameplay ending condition.
        "truncated": get_episode_step() + 1 >= episode_length,
    }
```

`get_episode_step()` counts completed successful steps; add one when deciding
whether the current step reaches your limit. Reset remains a separate optional
`_reset_episode(seed, options)` hook: it returns no step result and awards no reward.
Initial reset observations have empty `info`. The old `_get_reward`,
`_is_terminated`, `_is_truncated`, and `_get_info` hooks are replaced by
`_get_step_result`; they are no longer called.

To exercise the C++ adapter through GdUnit4, build with the test-only driver enabled:

```sh
scons -C Godot platform=windows target=template_debug integration_tests=yes
godot --headless --path Godot --import
godot --headless --path Godot -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests/integration/environment_step_result_test.gd
```

Use the platform appropriate to your machine. Normal builds omit the driver;
the adapter suite is skipped when it is unavailable.

The driver is a test-only bridge, not a production training host. Running an
ordinary scene does not automatically initialize, reset, or step its environments.
The current `examples/basic_environment/` scene is a registration probe. A gameplay
example is outside US5's scope. `ScholaTrainingHost` supplies the production host;
its integration-test environment uses `_get_step_result` for reward and completion.

CI builds with `integration_tests=yes` so the adapter suite is exercised. Builds
intended for distribution should omit that option to exclude the test driver.

### Editor and runtime monitor

The **AMD Schola** editor plugin uses GDScript and works in standard Godot without .NET. It is enabled in this project. Reopen the project after updating, or enable it in **Project → Project Settings → Plugins**.

- Open the **Schola** dock beside the Inspector to see which native Schola classes are actually available. Refresh after changing the scene tree. Select a listed node to configure its existing properties in the Inspector.
- Use **Add monitor to current scene** to insert a `CanvasLayer` and `ScholaMonitor`, with editor undo/redo support. You can also search for **ScholaMonitor** in Add Node. Its title and history limit are editable in the Inspector.
- Use **Open interactive UI preview**, then **F6**, to inspect the runtime panel. Alternatively open `res://examples/ui_preview/main.tscn` directly. Next step, auto play/pause, new episode, terminate, and truncate operate on explicitly synthetic telemetry. This preview does not run a trainer or implement an RL environment.

The runtime monitor displays episode and step counts, cumulative reward history, per-agent rewards and returns, and termination/truncation state. Feed it real data from the component that owns the lifecycle, on the Godot main thread:

```gdscript
@onready var monitor: ScholaMonitor = $ScholaHUD/ScholaMonitor

func start_display_episode() -> void:
    monitor.begin_episode(1, PackedStringArray(["player"]), 500)

func display_step(reward: float) -> void:
    monitor.record_step({"player": reward}) # Incremental reward, once per step.

func display_episode_end(truncated: bool) -> void:
    monitor.end_episode(truncated)
```

Each `record_step` call represents one environment step. Only IDs declared at the start of that episode are accepted; invalid reward batches are rejected together. Calls after episode end are ignored until the next `begin_episode`. The monitor does not control the environment or automatically end an episode at the displayed limit. The lifecycle owner supplies the actual end event. Missing native capabilities remain labeled unavailable in the editor dock.

After installing the test dependencies described above, run the UI checks with:

```sh
godot --headless --path Godot \
  -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --ignoreHeadlessMode -a res://tests/integration/ui_test.gd
```

## Running a trained policy

A policy exported to ONNX runs inside Godot without Python. Add a `ScholaOnnxPolicy` resource whose `model_path` points to the `.onnx` file, and a `ScholaInferenceStepper` node whose `policy` is that resource and whose `agents` lists the `ScholaAgent` nodes to drive. The stepper loads the model, checks it against the agents' spaces, and runs observe, infer, and act every physics frame. For a custom loop, call `ScholaOnnxPolicy.initialize(agent)` and then `infer(observation, state)`.

Exported games need two export preset filters: add `*.onnx` to the non-resource files to export, and exclude `addons/schola_training/*`. The ONNX Runtime library is exported automatically with the runtime add-on. Release exports also need the extension built with `target=template_release`. See [`docs/us7_inference_api.rst`](docs/us7_inference_api.rst) for the full guide, recurrent models, the model contract, and error handling.

## Directory structure

```text
Godot/
├── src/
│   ├── core/
│   │   ├── common/               Shared IDs and status values
│   │   ├── connector/            Engine-independent connector loop
│   │   ├── environment/          Environment and agent contracts
│   │   ├── spaces/               Observation/action spaces and point values
│   │   ├── lifecycle/            Step, reset, and auto-reset coordination
│   │   ├── policy/               Engine-independent policy and policy state contracts
│   │   └── stepper/              Engine-independent observe, think, and act loop
│   ├── bindings/
│   │   ├── environment/          Godot environment and agent nodes
│   │   ├── inference/            Godot-facing policy and inference APIs
│   │   └── spaces/               Inspector space resources
│   ├── inference/                ONNX Runtime policy module
│   ├── interop/                  Godot Variant and core value conversion
│   ├── runtime/                  Runtime extension composition root
│   ├── training/
│   │   └── bindings/             Training-only Godot integration
│   └── transport/grpc/           gRPC and Protocol Buffer integration
├── addons/
│   ├── schola/                   Runtime add-on packaging
│   └── schola_training/          Training-only add-on packaging
├── examples/
│   └── basic_environment/       End-to-end demonstration environment
└── tests/
    ├── unit/                    Fast tests for individual modules
    └── integration/             Cross-module and Python compatibility tests
```

## Module boundaries

### `src/core`

Contains shared status and identifier values, engine-independent environment interfaces, space and point types, agent state, lifecycle coordination, the connector loop, and the policy and stepper contracts. It must not reference Godot, gRPC, Protocol Buffer, or ONNX Runtime libraries.

`src/core/spaces/` defines `schola::Space` (Box, Discrete, MultiDiscrete, MultiBinary, and Dict definitions) and `schola::Point` (values in those spaces). Spaces report malformed definitions (`INVALID_DATA`) and invalid points (`INVALID_ARGUMENT`) through the shared `schola::Status` in `src/core/common/`. Dict entries are ordered, and that order fixes the flattened layout exchanged with Python.

### `src/bindings`

Adapts the core abstractions to user-facing Godot nodes, resources, the Inspector, and the engine lifecycle. User-facing Godot APIs belong here. The `src/runtime` and `src/training` composition roots may use the minimal Godot registration APIs needed to assemble and initialize their extensions; they must not define user-story APIs.

### `src/transport/grpc`

Contains the gRPC adapter boundary for Schola's existing Protocol Buffer contract. The public adapter API is merged; dependency acquisition, generated bindings, and runtime behavior remain implementation work. Keeping the adapter separate prevents networking dependencies from leaking into the core or inference-only builds.

### `src/inference`

Contains ONNX Runtime policy integration for local inference without a running Python process or training connection. It is the only module that includes ONNX Runtime headers; the policy and stepper contracts it implements live in `src/core/policy/` and `src/core/stepper/`. The Godot-facing classes live in `src/bindings/inference/` and register through `src/inference/register_types`. Inference remains independent from the training extension so exported games can exclude training dependencies.

The inference API follows the policy state design of Unreal Schola. A policy holds no per-agent data. Each agent's memory, such as the hidden tensors of a recurrent model, is a `schola::PolicyState` created by `Policy::create_initial_state()` and owned by the caller, so one loaded model can serve many agents. Policies without memory use `EmptyPolicyState` (Unreal: `UStatelessPolicyState`), so a state is never null. `SimpleStepper` owns one state per entry, keeps entries in add order like an array, and allows the same agent to be added more than once with a separate state for each entry. Differences from Unreal follow the project contract and Godot conventions: core functions return `schola::Status` instead of logging, `add_agent()` reports its index through an output parameter, and the Godot-facing `ScholaInferenceStepper` takes agent nodes instead of indices and returns `Error`.

### `src/interop`

Converts between Godot `Variant` values and engine-independent core values. This directory is compiled into both extensions so the training extension can communicate through bound Godot methods without linking directly to runtime-extension C++ classes.

### `src/runtime` and `src/training`

These directories are the composition roots for the runtime and training extensions. User-story APIs live in their owned modules; the composition roots register and assemble those modules.

### Godot add-ons

- `addons/schola/` contains runtime functionality required by both development projects and exported games.
- `addons/schola_training/` contains training and communication integration. Exported games must be able to exclude this add-on while retaining runtime inference.

## Dependency direction

```text
bindings ──→ core ←── inference
               ↑
        training transport
```

Dependencies must point toward `core`. The core must never depend on Godot bindings, gRPC, Protocol Buffers, or ONNX Runtime. The training add-on may depend on the runtime add-on, but the runtime add-on must not depend on training code.

## User-story mapping

| User story | Primary location |
| --- | --- |
| US1: Define an environment | `src/core/environment/` |
| US2: Declare spaces | `src/core/spaces/` |
| US3: Connect Python training tools | `src/core/connector/`, `src/transport/grpc/`, `src/training/bindings/`, and `addons/schola_training/` |
| US4: Execute the episode lifecycle | `src/core/lifecycle/` and the Godot-facing training host |
| US5: Configure through Godot | `src/bindings/` and `examples/basic_environment/` |
| US7: Run and ship an ONNX policy | `src/core/policy/`, `src/core/stepper/`, `src/inference/`, `src/bindings/inference/`, and `addons/schola/` |

The detailed acceptance criteria and D1 planning scope are in [`deliverables/D1/planning.md`](../deliverables/D1/planning.md). Engineering tasks, dependencies, assignees, and progress are tracked on the team's [Trello board](https://trello.com/b/Ry0Qkx2R).

The merged headers in each primary location define the current user-story interfaces. Changes to a cross-story contract require review from its producers and consumers.

## Format C++ code

Use clang-format 17 with [`Godot/.clang-format`](.clang-format). The [`Godot/.editorconfig`](.editorconfig) file configures compatible whitespace and line-ending defaults for supported editors. Coding conventions that are not enforced mechanically belong in the [development contract](docs/development_contract.md#c-conventions).

Install the pinned formatter package on Linux, macOS, or Windows:

```sh
python -m pip install --require-hashes -r Godot/requirements-format.txt
```

From the repository root, format all tracked Godot C++ files with:

```sh
git ls-files ':(glob)Godot/**/*.cpp' ':(glob)Godot/**/*.h' | xargs clang-format -i
```

Check formatting without modifying files with:

```sh
git ls-files ':(glob)Godot/**/*.cpp' ':(glob)Godot/**/*.h' | xargs clang-format --dry-run --Werror
```

Run the check before opening a pull request. Format only team-owned source files. Repository workflow, testing expectations, generated-file rules, and review requirements are defined in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Archived Deliverable 1 demo

The original C#/.NET demo is preserved in [`archive/d1_demo/`](archive/d1_demo/) as a historical reference. It is not the production add-on and requires Godot .NET to run. The production add-on is the native C++ GDExtension described above; its environment and reward APIs are still under development, so the archived demo has not been ported.
