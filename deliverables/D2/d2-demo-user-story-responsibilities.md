# D2 demo: user-story responsibilities and scope

## Purpose

The D2 demo will show one small but complete reinforcement-learning workflow. The
Python client drives the conversation, matching Schola's existing `GymService`
contract:

```text
Python client                 Godot Schola plugin
     |-- start(mode) ----------------->|
     |<--------------- start result --|
     |-- definition request ---------->|
     |<------------------- definition -|
     |-- update(reset) --------------->|
     |<------------ initial state -----|
     |-- update(step with actions) --->|
     |<-- observation/reward/done -----|
     |-- update(close) --------------->|
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
- The temporary JSON adapter preserves the request order and roles of Schola's
  `StartGymConnector`, `RequestTrainingDefinition`, and `UpdateState` calls.
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

US3 is therefore only partially complete at D2. The demo implements the connector
loop and a compatible local JSON/TCP adapter, but it does not satisfy the final
gRPC/Protocol Buffer acceptance criteria or demonstrate an unmodified Schola
Python client. This scope decision should be confirmed with AMD before the demo.

## Architectural ownership rule

Reusable code belongs in `Godot/src/` and is implemented/tested as a plugin
feature. The D2 scene belongs under `Godot/demos/d2_training_workflow/` and uses
the plugin as a normal Godot developer would. It must not duplicate lifecycle
coordination, connector logic, or policy loading.

| Category | Location | Examples |
| --- | --- | --- |
| Persistent plugin code | `Godot/src/core/`, `Godot/src/bindings/`, `Godot/src/interop/`, `Godot/src/training/`, `Godot/src/transport/`, `Godot/src/inference/` | Space validation, Godot nodes, step coordinator, backend interface |
| Persistent tests | `Godot/tests/` | Space validation, reset behavior, connector-loop and message handling |
| Demo-only code | `Godot/demos/d2_training_workflow/` | Arena layout, goal/hazard visuals, movement mapping, HUD design |
| Demo-support code | A clearly named directory under the D2 demo | Local Python reference client and simple example policy |

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

US2 defines observations and actions and checks that the values passed through
them are valid.

### To build into the plugin

- `Box` and `Discrete` space definitions, with tests.
- Point values that hold data for those spaces.
- Checks that reject malformed spaces and invalid observations or actions.
- A fixed flattening and value order, where a transport or a future policy backend
  needs one.
- APIs that allow `MultiDiscrete`, `MultiBinary`, and `Dict` to be added later
  without changing the lifecycle or the Godot environment contract.

### To build only for the demo

- One `Box` observation, for example `[agent_x, agent_y, goal_dx, goal_dy]`.
- One `Discrete(4)` action mapped to up, down, left, and right.
- Formatting that shows these values in the telemetry UI.

### Keeping it general

The plugin will never assume that `Discrete(4)` means movement or that a `Box`
holds positions. The game developer declares each space and decides what its
values and actions mean. The D2 scene uses the general building blocks.

### Definition of done for D2

The `Space::validate()` API will reject an observation with the wrong shape and an
action outside its declared range, and it will accept the values the demo uses.
The D2 Python reference client validates actions before sending them. The US4
training path continues to forward points without an engine-side value scan, as
required by its approved contract.

## US3 — Connector and training transport

### Responsibility

US3 owns the Python-driven boundary between the engine-side RL loop and an
external trainer or policy provider. Godot listens; Python connects and initiates
each request.

### Persistent plugin implementation

- The transport-independent `Connector` interface.
- The `ConnectorLoop` implementation, preserving this call order:
  `StartGymConnector`, `RequestTrainingDefinition`, then repeated `UpdateState`
  calls.
- Handling for all `UpdateState` operations: reset, step with actions, and close.
- `HostTrainingBackend`, which adapts the connector loop to the US4-owned
  `ScholaTrainingHost` on the Godot main thread.
- Registration and runtime setup of `ScholaTrainingConnector` in Godot.
- Connection-state reporting for waiting, connected, training, closed, and error
  states, including a Godot signal/property usable by the telemetry panel.
- `FakeConnector` and connector-loop unit tests that do not require Python or a
  network connection.
- Error propagation from the backend or transport to the pending Python call.

### D2-specific or temporary implementation

- A newline-delimited JSON connector over a localhost TCP socket. Godot listens on
  the configured port (default `8000`) and Python connects to it.
- JSON messages that mirror the three `GymService` calls one-to-one: `start`
  carrying the auto-reset mode, `definition`, and `update` carrying reset, step
  with actions, or close.
- A Python reference client that initiates those calls, validates the action it
  sends, and implements the simple D2 policy. Although stored with the demo, its
  protocol behavior is part of US3's D2 responsibility.
- Demo documentation for choosing the port and starting the Godot and Python
  processes.

### Extensibility requirement

The JSON adapter must implement `Connector` and preserve the real Schola call
roles rather than being called directly from Godot scene code. Replacing it with
`GrpcConnector` must not change the connector loop, training backend, lifecycle,
or scene. This keeps Gymnasium, SB3, RLlib, remote training, and user-built
backends viable without rewriting environments.

Episode and step counters are not transport fields. They do not belong in
`TrainingState`, `StepResult`, or the JSON equivalents. If Python needs them for
diagnostics, they may be added to the existing text `info` map rather than to the
shared protocol types.

### D2 completion check

Godot listens on the configured localhost port. The Python reference client can
complete start, definition, reset, repeated step, and close calls in Python's
request order. The connector loop returns each matching Godot response and reports
connection, malformed-message, backend, and shutdown errors clearly.

This completes the D2 JSON/TCP path, not the final US3 gRPC acceptance criteria.

## US4 — Episode lifecycle

### Responsibility

US4 owns the reusable sequencing of an RL episode.

### Persistent plugin implementation

- Reset/start behavior when requested by Python.
- The generic sequence: receive a reset and reply with the first observation;
  receive actions, apply them, collect the next observation/reward/done flags,
  and reply with the new state.
- Episode and step counters exposed as read-only local telemetry. These counters
  are not added to the transport types.
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
- Signals/callable hooks for reset requests, actions received, and episode end.
- Read-only access to the US4 episode/step counters needed by the demo telemetry.
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
and C++/GDExtension users where feasible. Connection state is owned and exposed
by the US3 `ScholaTrainingConnector`; the demo UI consumes that state alongside
the US4 counters.

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

- A D2 implementation of the Python side of the start, definition, and update
  calls, connecting to Godot over localhost TCP.
- Validation of actions before they are sent to Godot, matching US4's rule that
  Python owns point validation.
- A transparent policy approach: random, rule-based, or a small tabular learner.
- Logging of episodes and reward progression.
- Writing the D2 policy artifact if US7 scope is completed.

### The example must not include

- A second implementation of core spaces, lifecycle logic, or transport APIs.
- Hidden scripted behavior presented as model training.
- Claims of full gRPC, SB3/RLlib, or ONNX support before those integrations work.

## Integration sequence

1. Confirm with the US3/US4 owners that Python initiates calls, Godot listens on
   localhost TCP, and Python owns action validation.
2. Finish and test US2 (`Box` and `Discrete`) and US1 contracts.
3. Implement/test US4's single-agent episode loop and local telemetry counters.
4. Implement US5 Godot classes and connect them to a simple scene.
5. Implement US3's `ConnectorLoop`, `HostTrainingBackend`, Godot registration,
   connection-state API, `FakeConnector`, and tests.
6. Implement the JSON/TCP `Connector` and matching Python reference client using
   the real start, definition, and update request order.
7. Integrate the D2 scene and telemetry UI.
8. Add US7's minimal load/run demonstration only after the training loop is
   reliable.
9. Package the example, document setup, record the walkthrough, and tag the
   tested D2 release.

## Definition of done for the D2 vertical slice

The team can start one Godot example, connect the Python reference client to the
Godot listener, complete the start/definition/update conversation, watch
success/failure resets, and understand each stage through the UI. The underlying
reusable code remains generic enough for another Godot project to provide
different spaces, gameplay behavior, reward rules, and a different training
backend. The D2 report explicitly records that the JSON/TCP adapter demonstrates
the connector architecture while production gRPC/Protocol Buffer integration
remains unfinished US3 work.
