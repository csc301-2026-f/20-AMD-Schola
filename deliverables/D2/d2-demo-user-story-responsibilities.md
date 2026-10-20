# D2 demo: user-story responsibilities and scope

## Purpose

The D2 demo will show one small but complete reinforcement-learning workflow:

```text
Godot environment
  -> produces an observation and receives an action
Schola plugin
  -> validates data, coordinates steps, and communicates with a backend
Local Python demo client
  -> selects actions and saves a small policy artifact
Godot environment
  -> loads that artifact and runs the policy locally
```

The demo is intentionally small: one agent, a compact arena, a `Box` observation,
and a `Discrete` movement action space. This is an example configuration, **not** a
restriction on the final plugin. The reusable plugin must let a Godot developer
choose their own observations, actions, reward logic, episode conditions, and
training backend.

## Scope boundary

### D2 must demonstrate

- A Godot developer can configure a Schola environment and agent.
- A scene can supply observations, accept actions, report rewards, and finish or
  reset episodes.
- The plugin can exchange one complete episode loop with a local Python process.
- The demo makes the loop visible through status and telemetry UI.
- A small externally produced policy artifact can be loaded and used in the same
  scene, if the core transport/lifecycle path is stable.

### D2 does not claim to demonstrate

- Stable-Baselines3, RLlib, or distributed training.
- Production gRPC/Protocol Buffer transport.
- ONNX export or ONNX Runtime inference.
- Multi-agent orchestration, recurrent policies, batching, or every supported
  Gymnasium space type.
- A general-purpose training UI or a production-ready trainer.

## Architectural ownership rule

Reusable code belongs in `Godot/src/` and is implemented/tested as a plugin
feature. The example scene belongs under `Godot/examples/` and uses the plugin as
a normal Godot developer would. It must not duplicate space validation, lifecycle
coordination, connector logic, or policy loading.

| Category | Location | Examples |
| --- | --- | --- |
| Persistent plugin code | `Godot/src/core/`, `Godot/src/bindings/`, `Godot/src/interop/`, `Godot/src/training/`, `Godot/src/transport/`, `Godot/src/inference/` | Space validation, Godot nodes, step coordinator, backend interface |
| Persistent tests | `Godot/tests/` | Invalid action validation, reset behavior, connector message handling |
| Demo-only code | `Godot/examples/<d2-demo>/` | Arena layout, goal/hazard visuals, movement mapping, HUD design |
| Demo-support code | A clearly named demo/example Python directory | Local reference client and simple example policy |

## US1 — Core environment and agent

### Responsibility

US1 owns the engine-independent environment and agent contracts. For D2, it must
provide the core representation needed to identify an agent and describe the
information required to interact with its environment.

### Persistent plugin implementation

- Stable environment and agent identifiers/types.
- An engine-independent definition of an agent's observation and action spaces.
- Interfaces through which an environment can expose observations and receive
  actions.
- Shared types for reward, termination, truncation, and step results where these
  do not already belong to US4.
- Unit tests that prove the contracts do not depend on Godot, Python, networking,
  or a particular game.

### Demo-only implementation

- One arena agent and its concrete gameplay state.
- The particular observation contents used by the arena, such as agent position
  and relative goal position.
- The arena's movement speed, target location, hazard behavior, and art.

### Extensibility requirement

US1 must not assume that every agent is a moving 2D character. A future user may
control a vehicle, camera, turn-based unit, or simulation parameter. The plugin
provides contracts; the Godot project supplies the game-specific implementation.

### D2 completion check

The lifecycle layer can identify one agent and request its declared spaces without
referencing the D2 scene.

## US2 — Spaces and points

### Responsibility

US2 owns general definitions and validation for observations and actions.

### Persistent plugin implementation

- Correct, tested `Box` and `Discrete` space definitions.
- `Point` values that represent data belonging to those spaces.
- Validation for malformed spaces and invalid points/actions.
- A stable flattening/value-ordering convention where required by a transport or
  future policy backend.
- APIs designed so `MultiDiscrete`, `MultiBinary`, and `Dict` can be added without
  changing the lifecycle or Godot environment contract.

### Demo-only implementation

- A particular `Box` shape, for example `[agent_x, agent_y, goal_dx, goal_dy]`.
- A particular `Discrete(4)` action mapping: up, down, left, and right.
- Display formatting for these values in the telemetry UI.

### Extensibility requirement

The plugin must never hard-code that `Discrete(4)` means movement or that a `Box`
contains position values. The game developer declares the space and maps its own
values/actions. The D2 scene is one consumer of the generic primitives.

### D2 completion check

The plugin rejects an incorrectly shaped observation and an action outside the
declared range, while accepting the values used by the demo.

## US3 — Connector and training transport

### Responsibility

US3 owns the boundary between the engine-side RL loop and an external trainer or
policy provider.

### Persistent plugin implementation

- A backend/connector interface independent of a specific transport.
- A well-defined step payload containing observation, reward, terminated,
  truncated, and episode/step information.
- A response representation containing the requested action and useful error
  status.
- Connection lifecycle and error propagation that can be surfaced to Godot.
- Tests using a fake/in-process backend so core behavior can be verified without
  starting Python.

### D2-specific or temporary implementation

- One simple local transport to a Python process, chosen for reliability and
  speed of implementation (for example newline-delimited JSON over standard I/O
  or a localhost socket).
- The message schema for that temporary adapter, if it differs from the planned
  gRPC/Protocol Buffer implementation.
- Process-launch details and command defaults for the D2 example.

### Extensibility requirement

The local adapter must implement the connector interface rather than being called
directly from Godot scene code. This keeps gRPC/Protobuf, Gymnasium, SB3, RLlib,
remote training, or a user-built backend viable without rewriting environments.

### D2 completion check

The Godot plugin can send step data to a local Python client, receive a valid
action, and report a clear error if the client is unavailable or returns invalid
data.

## US4 — Episode lifecycle

### Responsibility

US4 owns the reusable sequencing of an RL episode.

### Persistent plugin implementation

- Reset/start behavior.
- The generic sequence: observe -> request action -> apply action -> collect
  reward and next observation -> report terminal/truncated state.
- Episode and step counters.
- Correct reset behavior after success, failure, timeout, or backend-requested
  restart.
- Tests for normal completion, truncation, repeated reset, and invalid backend
  response handling.

### Demo-only implementation

- The condition "agent touches target" as success.
- The condition "agent hits hazard" as failure.
- The demo's maximum step count and visual reset animation/message.
- The demo's chosen reward values.

### Extensibility requirement

US4 coordinates events but does not calculate game-specific reward or decide what
a goal means. A developer's Godot code supplies the observation and step outcome;
the plugin applies the generic episode protocol.

### D2 completion check

The scene runs several complete episodes automatically, correctly reporting
rewards and states to Python and resetting between episodes.

## US5 — Godot-facing bindings

### Responsibility

US5 turns the reusable C++ contracts into Godot-native classes that developers can
add to scenes, configure in the Inspector, and connect to gameplay scripts.

### Persistent plugin implementation

- Registered `ScholaEnvironment` and `ScholaAgent` Godot classes.
- Inspector properties for generic configuration, such as spaces, episode limits,
  and backend selection/configuration.
- Signals/callable hooks for reset requests, actions received, episode end, and
  connection/status changes.
- Variant-to-core conversion and clear Godot error reporting.
- Documentation/example snippets explaining how a developer supplies their own
  observation, action application, reward, and terminal logic.

### Demo-only implementation

- The exact node layout of the arena scene.
- The specific UI widget locations, colours, labels, and control hints.
- The demo's button labels, such as **Start Local Training** or **Load Demo Policy**.
- A scene script that maps actions to the arena's movement methods.

### Extensibility requirement

The bindings must expose hooks rather than requiring one fixed `Player` node,
movement system, or reward formula. The plugin should be useful to both GDScript
and C++/GDExtension users where feasible.

### D2 completion check

A developer can inspect the D2 scene, see how Schola nodes are configured, and
connect a different Godot gameplay implementation without modifying plugin source.

## US7 — Policy loading and local action selection

### Responsibility

US7 is the long-term inference story. D2 should only take the smallest reliable
step toward it after US1–US5 and US3 work end to end.

### Persistent plugin implementation

- A generic policy/policy-state interface suitable for local action selection.
- Clear separation between a policy model and per-agent state.
- A loader boundary that can later host an ONNX Runtime implementation.
- Validation and helpful errors when a policy artifact is missing or incompatible
  with an agent's declared spaces.

### D2-specific or temporary implementation

- A deliberately small policy artifact such as JSON containing a deterministic
  action table or rule configuration.
- A reference loader/evaluator for that format.
- The demo-mode toggle between an external Python-controlled agent and the loaded
  local policy.

### Extensibility requirement

The JSON artifact is a D2 teaching/demo format, not a replacement for ONNX. Keep
it behind the policy interface so ONNX Runtime can later be introduced without
changing the Godot environment or lifecycle APIs.

### D2 completion check

If the preceding vertical slice is stable, the demo can save/load a small external
policy artifact and visibly switch the agent to local policy control. If time is
limited, this is lower priority than a functioning connector and episode loop.

## Demo integration responsibilities

The D2 example is responsible for presentation and composition, not duplicated
plugin logic.

### The example scene includes

- A minimal arena with one agent, target, and optional hazard/timeout.
- A developer-facing configuration view in the Inspector.
- A runtime status panel showing connection state, mode, current episode/step,
  reward, last observation, last action, and terminal result.
- A compact reward history or running-average display.
- Clear visual feedback for start, success, failure, reset, and loaded-policy
  mode.

### The example Python client includes

- The D2 connector protocol implementation.
- A transparent policy approach: random, rule-based, or a small tabular learner.
- Logging of episodes and reward progression.
- Writing the D2 policy artifact if US7 scope is completed.

### The example must not include

- A second implementation of core spaces, lifecycle logic, or transport APIs.
- Hidden scripted behavior presented as model training.
- Claims of full gRPC, SB3/RLlib, or ONNX support before those integrations work.

## Integration sequence

1. Finish and test US2 (`Box` and `Discrete`) and US1 contracts.
2. Implement/test US4's single-agent episode loop.
3. Implement US5 Godot classes and connect them to a simple scene.
4. Implement US3's local Python adapter and demonstrate live action exchange.
5. Add the D2 scene, telemetry UI, and reference Python client.
6. Add US7's minimal load/run demonstration only after the training loop is
   reliable.
7. Package the example, document setup, record the walkthrough, and tag the
   tested D2 release.

## Definition of done for the D2 vertical slice

The team can start one Godot example, observe a configured Schola environment
exchange live steps with Python, watch automatic success/failure resets, and
understand each stage through the UI. The underlying reusable code remains generic
enough for another Godot project to provide different spaces, gameplay behavior,
reward rules, and a different training backend.
