# Schola for Godot

This directory contains the Godot port of AMD Schola. The design keeps reusable reinforcement-learning logic independent from Godot, gRPC, and ONNX so that each part can be developed and tested separately.

Repository workflow and contribution requirements are defined in [`CONTRIBUTING.md`](../CONTRIBUTING.md). Binding engineering rules are defined in the [`Godot development contract`](docs/development_contract.md). This guide contains the supported toolchain and executable development commands.

## Current D3 example and automation

The [D3 demo](demo/d3/README.md) exercises the native environment/agent adapters, `ScholaTrainingHost`, and ONNX inference. It uses only the runtime extension: build with the `schola` target to avoid installing or linking the unfinished production gRPC transport. The demo's localhost JSON/TCP connector and tabular trainer remain temporary integration code.

The [Godot workflow](../.github/workflows/godot.yml) runs formatting, native and Godot tests, D3 reference-policy playback, and a two-instance, 20-episode training/export/playback check. [D3 packaging](../.github/workflows/d3-release.yml) builds debug/release runtime libraries and desktop packages, checks both source and exported applications, and participates in the aggregate required PR check. Successful `main` runs publish commit-specific development prereleases; the `D3` tag publishes the final course snapshot. Manual dispatch and `D3-test-*` tags produce artifacts without publishing. Confirm platform results in Actions before describing a package as verified.

Every runner job has a timeout. Native compilation, especially cold debug/release builds of `godot-cpp`, needs a longer allowance than formatting and publication; SCons output caches reduce repeated work. The optional source rebuild of gRPC has its own 90-minute limit and does not run in normal PR checks or D3 packaging. Standard GitHub-hosted runners for this public repository do not consume the course organization's shared private-repository minutes allocation.

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

Dependency decisions are centralized in [`dependencies.lock.json`](dependencies.lock.json). `godot-cpp` and Catch2 are pinned Git submodules, and CI verifies that their checked-out commits match the lock. ONNX Runtime 1.30.0 (CPU, C API) is pinned for Windows x86_64, Linux x86_64, and macOS arm64. Prebuilt packages repacked from the signature-verified Microsoft NuGet distribution are committed with Git LFS under [`vendor/onnxruntime/`](vendor/onnxruntime/README.md). Fetch them with `git lfs pull --include="Godot/vendor/onnxruntime/*.tar.gz" --exclude=""`, then run `python Godot/tools/setup_onnxruntime.py` to checksum-verify and install the host package into the git-ignored `thirdparty/onnxruntime/`. Installation requires no upstream download. Run the script before building. Only the runtime extension links ONNX Runtime, and the build installs its library next to `schola` so exported games include it. ONNX Runtime has no universal macOS package, so macOS builds use `arch=arm64`.

gRPC 1.80.0 and the Protocol Buffers 31.1 release it bundles are pinned to the same versions as Unreal Schola, pending AMD confirmation. Godot-specific Windows/Linux x86_64 prebuilt packages are committed under [`vendor/grpc/`](vendor/grpc/), including headers, static libraries, matching generators, licenses, and build provenance. Run `uv run --no-project --python 3.12 python Godot/tools/setup_grpc.py` locally to verify and unpack the host package into the git-ignored `thirdparty/grpc/`; normal installation never compiles or downloads gRPC. CI uses the same installer with its existing Python setup. Missing or incompatible packages fail clearly. See the [package and rebuild guide](vendor/grpc/README.md) for explicit source builds and other platforms. SCons generates GymService bindings from the shared `Proto/` directory into `generated/proto/`. Only the training extension links gRPC and protobuf; Unreal's binaries are not reused.

For an explicit source rebuild on Windows, install the Visual Studio C++ Build Tools and Windows SDK, then run setup from an **x64 Native Tools Command Prompt for VS 2022** or an x64 Visual Studio Developer PowerShell. For Ninja builds, select MSVC explicitly before running setup:

```powershell
$env:CMAKE_GENERATOR = "Ninja"
$env:CC = "cl"
$env:CXX = "cl"
Get-Command cl,ninja,cmake
uv run --no-project --python 3.12 python Godot/tools/setup_grpc.py --from-source --force --work-dir C:\grpc
```

Ninja must be installed and available on `PATH`. Setup selects the static MSVC runtime for gRPC, c-ares, protobuf, and Abseil to match `godot-cpp`. An explicit `--work-dir` is deleted and recreated on each build attempt, including read-only Git pack files; use a directory dedicated to this build. Setup regression tests run locally with `uv run --no-project --python 3.12 python -m unittest discover -s Godot/tools -p test_setup_grpc.py -v`.

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

Tests for the gRPC transport and its Protocol Buffer conversions live under `tests/transport/` and build as a separate target that links gRPC:

```sh
scons -C Godot transport_tests platform=linux target=template_debug -j"$(nproc)"
./Godot/build/tests/schola_transport_tests
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

For manual environment debugging without Python or a transport connection,
run the [US9 example](examples/manual_environment/README.md). It uses the
runtime extension's existing `ScholaTrainingHost` API and supports explicit
reset, seeded starts, individual actions, and inspection of episode results.

Godot has an [upstream race](https://github.com/godotengine/godot/issues/98062) that can abort a completed headless import while editor add-ons are shutting down. If the import reaches completion and exits with status 134, rerun the import command. CI retries this step at most 3 times and still fails persistent import errors.

## Build and run

From a fresh checkout:

```sh
git submodule update --init --recursive
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --require-hashes -r Godot/requirements.txt
python Godot/tools/setup_onnxruntime.py
python Godot/tools/setup_grpc.py
scons -C Godot platform=linux target=template_debug -j"$(nproc)"
godot --editor --path Godot
```

On macOS, use `platform=macos arch=arm64` and replace `$(nproc)` with `$(sysctl -n hw.logicalcpu)`. On Windows, run `scons -C Godot platform=windows target=template_debug` from a developer shell; SCons selects a safe default job count when `-j` is omitted. Windows unit tests run from `Godot\build\tests\schola_core_tests.exe`. Build products are copied into the matching `Godot/addons/*/bin/<platform>/` directory and are not committed.

The `schola` target contains the runtime extension. The `schola_training` target is a separate training extension and may depend on runtime and core code while implementing the merged transport contracts. The example project loads `examples/basic_environment/main.tscn`, which instantiates `ScholaRuntimeProbe`. The runtime and training probe nodes exist only to verify extension registration and loading; they are not production APIs for any user story.

Use `scons -C Godot schola platform=linux target=template_debug` for a runtime-only build. The `schola`, `unit_tests`, and `inference_tests` targets do not require gRPC or generate protocol bindings. The default build, `schola_training`, and `transport_tests` require the installed gRPC package.

The extension entry points are stable composition roots. Runtime bindings and inference register through their own `register_types` files, and training-only bindings register through `src/training/bindings/register_types`. Feature branches add registrations only to the hook owned by their module; they do not add production classes directly to the runtime or training composition roots.

## Code-defined spaces example

The current [US15 example](examples/code_defined_spaces/README.md) demonstrates a
640×480 RGB observation and repeated nested limb/joint observations and actions.
It runs two short episodes locally through `ScholaTrainingHost`, using synthetic
pixels and joint values. It requires the runtime extension, without gRPC, Python
training, an ONNX model, or test-only bindings.

Build the runtime (Windows shown; use your platform as appropriate):

```powershell
scons -C Godot schola platform=windows target=template_debug
```

Open `Godot/examples/code_defined_spaces/main.tscn` in the editor and press F6.
Both Inspector space fields on Robot stay empty because `_define_spaces()` returns
a typed `ScholaSpaceDefinition` built with `ScholaSpaceDefinition.create(observation,
action)`. Adjust its exported dimensions and joint counts before starting the scene.
The example does not change the project's configured main scene.

For a headless check that exits with code 0 on success and 1 on failure:

```sh
godot --headless --path Godot res://examples/code_defined_spaces/main.tscn -- --us15-smoke-test
```

Expected output ends with `Passed: two episodes, 6 actions, one space-definition
callback.` for the default settings. The scene also shows a status summary when
run in a window. See the [space-definition API](docs/us15_space_definition_api.md)
for constructors, validation, and snapshot lifetime.

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

For direct agent hooks, assign `ScholaSpace` resources to `observation_space`
and `action_space`. Both start unassigned. When `_define_spaces()` is implemented,
it supplies both spaces and overrides
Inspector assignments. Otherwise, when descendant sensors or actuators
supply a side instead, its explicit property may remain unassigned. The saved
properties return only explicit configuration; `get_effective_observation_space()`
and `get_effective_action_space()` report explicit or component-composed resources
without executing `_define_spaces()` or exposing its saved result. The Inspector
offers Box, Discrete, MultiDiscrete, MultiBinary, and Dict resource types supplied
by US2, with inline help for their settings. Discrete and MultiBinary sizes start
at zero and require a positive value; their Inspector fields provide positive-size
range hints. Box dtype defaults to float32, and omitted bounds are unbounded.

Inherited `_define_spaces()` callbacks also take precedence. Invalid callback
results fail at startup without falling back to Inspector assignments. Inspector
warnings inspect metadata without executing the callback, including for `@tool`
scripts. Unused Inspector fields may remain empty or invalid; callback results do
not overwrite saved resources. Behavior hooks are still required unless components
provide that side. See the [space-definition API](docs/us15_space_definition_api.md).

Resources can be embedded in a scene or saved separately as `.tres` files. Shared
resources intentionally share configuration; use Godot's Make Unique operation
when an assignment needs an independent copy. The US5 owner has completed the
manual editor persistence checks.

Agent warning icons identify missing/invalid spaces and missing `_observe` or
`_act` hooks. The environment shows at most one summary per agent with warnings;
select that agent node for the specific diagnostics. The environment also reports
missing agents, missing `_get_step_result`, and duplicate resolved agent IDs, including the conflicting
node paths. Nested `ScholaEnvironment` nodes are unsupported: the Inspector warns
and training rejects environments with an environment ancestor, including through
grouping nodes. Separate non-nested environments may reuse agent IDs.
See [the nesting decision](docs/decisions/environment-nesting.md).
`_reset_episode` is optional.

Warnings refresh when resources (including nested Dict entries) or scripts change,
and when agents are added, removed, renamed, or reparented. Script-hook diagnostics
inspect inherited script metadata; gameplay scripts do not need `@tool`.
`get_configuration_errors()` checks Inspector resources for agents without
`_define_spaces()` and checks scene configuration; the editor
adds missing-hook warnings. Runtime adapter calls still validate required hooks
before invoking them.

Runtime startup checks scene structure separately and obtains spaces through
the agent's validated snapshot. Editing or clearing Inspector resources after
resolution does not invalidate the running definition; editor diagnostics still
report problems in those authored fields. Recreate the scene to apply new spaces.

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
  --ignoreHeadlessMode -a res://tests/integration/environment_step_result_test.gd \
  -a res://tests/integration/environment_adapter_test.gd
```

`environment_step_result_test.gd` covers result parsing and callback order.
`environment_adapter_test.gd` covers the rest of the adapter contract:
initialization, seeded resets, action checks before any agent moves, staggered
episode endings, freed agents, and `get_agents()` order.

Use the platform appropriate to your machine. Normal builds omit the driver;
the adapter suites are skipped when it is unavailable.

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
- Use **Open interactive UI preview**, then **F6**, to inspect the runtime panel. The button appears in this repository's project, where the preview scene lives. Alternatively open `res://examples/ui_preview/main.tscn` directly. Next step, auto play/pause, new episode, terminate, and truncate operate on explicitly synthetic telemetry. This preview does not run a trainer or implement an RL environment.

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

## Reusable sensors and actuators

See [US8 components](docs/us8_components.md) for GDScript sensor and actuator
nodes, ordered agent composition, ray sensing, movement, rotation, teleportation,
and real/fake camera components, including rendered color/depth capture tests.
Open [the interactive US8 example](examples/us8_components/README.md) to try
keyboard movement, automatic control, and live ray observations with F6.

## Train with Python

Add one `ScholaTrainingConnector` node to the scene you want to train, as with Unreal Schola's `AGymConnectorManager`. It trains every `ScholaEnvironment` in the current scene and creates its own `ScholaTrainingHost` as an internal child, so nothing else is needed. The connector comes from the training extension, which needs the committed gRPC package:

```sh
python Godot/tools/setup_grpc.py
scons -C Godot platform=linux target=template_debug -j"$(nproc)"
```

Use the platform options from [Build and run](#build-and-run) on other systems. The default build includes the training extension; `schola_training` builds only that one. The runtime-only `schola` target does not include the connector.

Start the scene first. On its first physics frame, after every node's `_ready()`, the connector listens on `127.0.0.1:<port>` and waits for Python. Then start Python within `start_timeout_sec`. The command below is the one documented for Unreal Schola and has not yet been verified against Godot. `editor` is the alias of the `external` simulator, which connects to an already running game instead of launching one:

```sh
schola sb3 train ppo editor --port 8000 --timesteps 100000
```

Once connected, each physics frame waits for Python's next reset or step and runs it, so an action and its reward land on the same frame. The game does not respond while it waits; that is expected during training.

When Python closes a session normally, the connector keeps the port and waits for Python's next session, as Unreal Schola does. `schola rllib train` relies on this: it connects once to read the agents and their spaces, closes, and connects again to train. Each session gets a fresh internal `ScholaTrainingHost`, with the same agent IDs and spaces. Training ends when a session fails, or when Python does not start another session within `start_timeout_sec` of closing one.

- `port` defaults to 8000. `-ScholaPort=<n>` on the command line overrides it, as in Unreal Schola, and is also accepted after `--` as a user argument.
- `start_timeout_sec` (default 45 s) matches the Python client's `environment_start_timeout`. `step_timeout_sec` defaults to 60 s. Set either to 0 to wait forever.
- `is_training()` is true while a session is running. `session_closed()` is emitted each time Python closes a session normally. `training_finished(error: String)` is emitted once, when training ends: with an empty string when Python finished normally, otherwise with the reason, which is also pushed as an error.

The connector does nothing in the editor. Keep it in a training-only scene: exported games normally exclude `addons/schola_training/`.

### Multiple agents

Every `ScholaAgent` under a `ScholaEnvironment` is trained in the same episode, as in Unreal Schola. The [two-agent example](examples/multi_agent/README.md) shows the pattern.

- **Identity.** Python identifies agents by their resolved agent ID (`agent_id`, or the node name), and lists them sorted by ID, not in scene order. IDs and spaces are fixed when the session starts and stay the same for every episode, and for every session if Python reconnects. Two agents with the same ID in one environment stop the session from starting.
- **Spaces.** Each agent declares its own observation and action spaces, which may differ. Agents with the same `agent_type` share a policy in RLlib.
- **Steps.** Python sends one action per unfinished agent. All of them act, in scene-tree order, before any agent is observed, so every observation sees the same world. `_get_step_result(agent)` then runs once per agent, so each agent can get its own reward, or the environment can give every agent a shared team reward.
- **Episode endings.** Each agent ends its own part of the episode by returning `terminated` or `truncated`. A finished agent no longer acts, and Python receives its final result unchanged on each later step. The episode ends when every agent has finished.
- **Protocol errors.** A step that leaves out an unfinished agent's action, or acts for a finished or unknown agent, is rejected before any agent moves, and it ends the training session.

Train agents with different spaces using RLlib (`schola rllib train`), which gives each agent its own policy and handles agents finishing on different steps. Schola's SB3 wrapper requires every agent to share one observation and action space, and every agent in an environment to finish on the same step.

## Running a trained policy

A policy exported to ONNX runs inside Godot without Python. Add a `ScholaOnnxPolicy` resource whose `model_path` points to the `.onnx` file, and a `ScholaInferenceStepper` node whose `policy` is that resource and whose `agents` lists the `ScholaAgent` nodes to drive. The stepper loads the model, checks it against the agents' spaces, and runs observe, infer, and act every physics frame. For a custom loop, call `ScholaOnnxPolicy.initialize(agent)` and then `infer(observation, state)` with an observation in the agent's final, adapted space.

Add a `ScholaStacker` Resource to the agent's `observation_adapters` array to give the policy recent observations. Keep the agent's `observation_space` and `_observe()` output in the original format. The agent applies Resources in array order and reports the final space to the trainer or policy. Set the output kind to Box for axis-based stacking or Dict for slot-suffixed keys. Slot zero is newest. An unset `default_point` uses the input space's default. Agents can share a stacker Resource and each agent keeps its own history. Training resets history automatically at episode start. With local inference, call the stepper's `reset_state(agent)` or `reset_states()` when starting an episode.

Exported games need two export preset filters: add `*.onnx` to the non-resource files to export, and exclude `addons/schola_training/*`. The ONNX Runtime library is exported automatically with the runtime add-on. Release exports also need the extension built with `target=template_release`. See [`docs/us7_inference_api.rst`](docs/us7_inference_api.rst) for the full guide, recurrent models, the model contract, and error handling.

## Dynamic training populations

Training definitions declare all **possible agent IDs** and their spaces once.
The active population may then change during an episode or between resets.
By default, the initial `ScholaAgent` descendants supply those definitions.
For future spawns, override `ScholaEnvironment._get_possible_agents()` to return
an `Array[ScholaAgent]` of definition templates for all possible IDs. Templates
may be outside the environment; the game owns their lifetime. Only actual
`ScholaAgent` descendants participate in the episode.

For example, keep definition-template nodes in a sibling container and assign
references through an exported array on your environment script:

```gdscript
@export var agent_templates: Array[ScholaAgent] = []

func _get_possible_agents() -> Array[ScholaAgent]:
    return agent_templates
```

The array must include every possible ID, including agents present initially.
Each spawned copy gets a unique unused ID from this declared roster.

Spawn a descendant with a declared ID, matching spaces, and matching `agent_type`.
Set `agent_id` explicitly so a node name collision cannot silently change its
identity. Schola returns a new agent's first observation with zero reward, and
Python supplies its first action on the following step.

In environments that override `_get_possible_agents()`, removing a live agent
finishes its trajectory. If `_get_step_result()` already ran, the departure keeps
the collected observation, reward, and info. Return `truncated: true` from that
hook for an external cutoff such as despawning at a level boundary. If the node
leaves before the hook runs, Schola sends the last observation with zero reward
and marks it terminated. Use `queue_free()` for removal from a gameplay callback.
An agent whose action was skipped due to detachment still finishes if reattached
later in the same step. Fixed-population environments report a freed or removed
agent as a training error.

Keep a published agent's resolved ID stable until reset. Renaming it between
requests or during dispatch closes the session before the stale action runs. An ID that terminates or truncates
is retired until reset. A node spawned with a retired ID is ignored for the rest
of that episode. Replacing a still-active node with another using the same ID
closes the session. To train a respawn in the same episode, use a new declared ID
such as `player_spawn_2` after `player_spawn_1` dies.

At reset, IDs may be reused with entirely new nodes. The initial roster reflects
the live population after reset and observation callbacks. Unused possible IDs
never need actions or delay completion. An episode completes when all observed
agents finish. An empty initial roster accepts an empty action map to discover
births.

This preserves the existing Python/protobuf possible-agent contract. It supports
a varying population within a declared capacity, rather than adding new space
definitions during training. Use a client supporting dynamic multi-agent rosters
(such as RLlib); SB3's fixed-size vector interface still requires fixed populations.

### Pause and resume training agents

Set `agent.training_paused = true` to suspend a live agent without terminating
its trajectory. Set it back to `false` to resume the same ID and node within the
episode. This affects training participation only; Godot processing and physics
continue normally.

```gdscript
waiting_unit.training_paused = true
# Later, when this unit can participate again:
waiting_unit.training_paused = false
```

Actions always match the last published roster. If a pause is requested after
an observation was published, Schola still runs the action requested for that
observation and collects its result. The pause takes effect at the step
boundary: the response omits the agent, and the client stops sending actions
for it. On resumption, a fresh observation and the held reward and info
complete that action. The next action is requested for the fresh observation.
Agents paused before their first published observation have no pending action
and join with zero reward when ready.

Observed paused agents keep the episode open, including when all agents are
paused. Continue stepping with empty action maps while Godot gameplay schedules
resumption. Initially paused agents are omitted from reset and participate only
after their first observation; unused IDs do not hold an episode open. Reset
preserves the property unless your `_reset_episode` changes it. Removing a paused
node still produces a terminal transition with any held reward. An ID that has
finished stays retired until reset. Pause state does not permit same-episode node replacement.

Use the updated Schola RLlib adapters for this scheduling behavior; they track
agents ready for actions separately from all episode participants. SB3 still
requires fixed populations and does not support pausing training agents.

To run the end-to-end RLlib sampler regression, build and import the Godot
project as above, install the Python test dependencies and the `rllib` extra,
then run from the repository root:

```sh
SCHOLA_TEST_GODOT=/path/to/godot python -m pytest Test/rllib/test_godot_dynamic_population.py -n 0
```

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

`src/core/adapters/` defines `schola::ObservationAdapter`, which transforms an agent's observations and reports the resulting space before training or inference. The Godot agent binding owns and applies the adapters in configuration order. `schola::BoxStacker` and `schola::DictStacker` keep a fixed-size observation history with the ordering and stacked-space rules of Unreal Schola's stackers. Index 0 is the newest observation. Adapter instances hold per-agent episode state and reset at the beginning of each episode.

### `src/bindings`

Adapts the core abstractions to user-facing Godot nodes, resources, the Inspector, and the engine lifecycle. User-facing Godot APIs belong here. The `src/runtime` and `src/training` composition roots may use the minimal Godot registration APIs needed to assemble and initialize their extensions; they must not define user-story APIs.

### `src/transport/grpc`

Contains the gRPC adapter boundary for Schola's existing Protocol Buffer contract. `GrpcConnector` is the server Python's trainer connects to. It receives calls on gRPC threads and hands each one to the Godot main thread. Keeping the adapter separate prevents networking dependencies from leaking into the core or inference-only builds.

### `src/inference`

Contains ONNX Runtime policy integration for local inference without a running Python process or training connection. It is the only module that includes ONNX Runtime headers; the policy and stepper contracts it implements live in `src/core/policy/` and `src/core/stepper/`. The Godot-facing classes live in `src/bindings/inference/` and register through `src/inference/register_types`. Inference remains independent from the training extension so exported games can exclude training dependencies.

The inference API follows the policy state design of Unreal Schola. A policy holds no per-agent data. Each agent's memory, such as the hidden tensors of a recurrent model, is a `schola::PolicyState` created by `Policy::create_initial_state()` and owned by the caller, so one loaded model can serve many agents. Policies without memory use `EmptyPolicyState` (Unreal: `UStatelessPolicyState`), so a state is never null. `SimpleStepper` owns one state per entry, and keeps entries in add order like an array. Differences from Unreal follow the project contract and Godot conventions: core functions return `schola::Status` instead of logging, `add_agent()` reports its index through an output parameter and rejects an agent that is already in the stepper, where Unreal would add a second entry that acts on the agent again each step, and the Godot-facing `ScholaInferenceStepper` takes agent nodes instead of indices and returns `Error`.

### `src/interop`

Converts between Godot `Variant` values and engine-independent core values. This directory is compiled into both extensions so the training extension can communicate through bound Godot methods without linking directly to runtime-extension C++ classes.

### `src/runtime` and `src/training`

These directories are the composition roots for the runtime and training extensions. User-story APIs live in their owned modules; the composition roots register and assemble those modules.

`src/training/bindings/` holds US3's `ScholaTrainingConnector` node and `HostTrainingBackend`. The backend calls the runtime's `ScholaTrainingHost` by method name, so the training extension never links runtime-extension C++ classes. Spaces cross as Dictionaries and points as Variants, converted with `src/interop`.

### Godot add-ons

- `addons/schola/` contains runtime functionality required by both development projects and exported games.
- `addons/schola_training/` contains training and communication integration. Exported games must be able to exclude this add-on while retaining runtime inference.

## Dependency direction

```text
bindings ──→ core ←── inference
               ↑
        training transport

training ──→ interop ──→ core
```

Dependencies must point toward `core`. Both extensions compile `src/interop`, which depends only on core and `godot-cpp`. The core must never depend on Godot bindings, gRPC, Protocol Buffers, or ONNX Runtime. The training add-on may depend on the runtime add-on, but the runtime add-on must not depend on training code.

## User-story mapping

| User story | Primary location |
| --- | --- |
| US1: Define an environment | `src/core/environment/` |
| US2: Declare spaces | `src/core/spaces/` |
| US3: Connect Python training tools | `src/core/connector/`, `src/transport/grpc/`, `src/training/bindings/`, and `addons/schola_training/` |
| US4: Execute the episode lifecycle | `src/core/lifecycle/` and the Godot-facing training host |
| US5: Configure through Godot | `src/bindings/` and `examples/basic_environment/` |
| US7: Run and ship an ONNX policy | `src/core/policy/`, `src/core/stepper/`, `src/inference/`, `src/bindings/inference/`, and `addons/schola/` |
| US10: Stack recent observations | `src/core/adapters/` |
| US12: Train multiple agents | `examples/multi_agent/` and `tests/integration/multi_agent_training_test.gd`, using the US1, US3, and US4 code above |

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

## Deliverable 1 demo

The original C#/.NET prototype is preserved in [`demo/d1/`](demo/d1/) as the frozen Deliverable 1 demo and requires Godot .NET to run. It is a historical prototype, not evidence of current production functionality. See the [demo index](demo/README.md) for milestone demos. The production add-on is the native C++ GDExtension described above.
