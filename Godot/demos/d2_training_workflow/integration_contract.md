# D2 demo integration contract

## Purpose

This document specifies the initial boundary between the D2 Godot scene and the
Schola plugin. It is an example integration, not a public restriction on Schola
environments.

## Scene-owned behavior

The D2 scene owns the game-specific parts of the example:

- Producing the observation values from the arena state.
- Applying a discrete movement action to the agent.
- Calculating the reward for the most recent step.
- Declaring success, failure, timeout, and visual reset behavior.

The scene exposes these placeholder methods on `D2DemoController`:

| Method | Expected eventual behavior |
| --- | --- |
| `get_observation()` | Return `[agent_x, agent_y, goal_dx, goal_dy]`. |
| `apply_action(action)` | Apply one `Discrete(4)` movement action. |
| `get_step_result()` | Return reward, terminal, and truncation information. |
| `reset_episode()` | Reset the arena for a new episode. |

## Plugin-owned behavior

The plugin, rather than the scene, owns:

- `Box` and `Discrete` space/point validation (US2).
- Environment and agent contracts (US1).
- The reset -> observe -> action -> reward -> terminal/truncated lifecycle (US4).
- Godot `ScholaEnvironment` and `ScholaAgent` nodes plus signals/bindings (US5).
- The connector interface and local Python adapter (US3).
- Optional D2 policy-artifact loading behind the generic policy interface (US7).

## Initial data contract

```text
Observation space: Box(4)
Observation order: [agent_x, agent_y, goal_dx, goal_dy]

Action space: Discrete(4)
0: move up
1: move down
2: move left
3: move right
```

`Space::validate()` can validate these values explicitly, and the D2 Python client
validates an action before sending it. The US4 engine-side training path forwards
points without an additional value scan, matching the approved lifecycle
contract.

## Connector conversation

Godot listens on a localhost TCP port (default `8000`) and Python connects. Python
initiates every operation. Newline-delimited JSON mirrors the existing
`GymService` calls:

```text
Python                         Godot
  |-- start(autoreset_mode) ---->|
  |<--------------- result ------|
  |-- definition ---------------->|
  |<--------------- definition --|
  |-- update(reset) ------------->|
  |<--------------- first state -|
  |-- update(step, actions) ----->|
  |<-- observation/reward/done ---|
  |-- update(close) ------------->|
```

The JSON/TCP adapter implements the shared `Connector` interface. Replacing it
with `GrpcConnector` later must not require changes to `ConnectorLoop`,
`HostTrainingBackend`, US4 lifecycle code, or the D2 scene.

Episode and step numbers are not part of `TrainingState`, `StepResult`, or the
transport schema. The UI reads them from US4's local lifecycle/host telemetry. If
Python needs them for diagnostics, they can be placed in the existing text `info`
map.

## Telemetry contract

The runtime panel will display connection state, control mode, episode number,
step number, cumulative reward, latest observation, latest action, and terminal
result. The panel is a visual consumer of plugin state; it must not perform
lifecycle coordination or transport work. Connection state comes from the US3
training connector; episode and step counters come from US4.

The US3 connection state exposed to Godot must distinguish at least waiting for
Python, connected, training, closed, and error.

## D2 limitation

The JSON/TCP connector demonstrates the intended request roles and connector
architecture, but it does not satisfy US3's final gRPC/Protocol Buffer acceptance
criteria or run an unmodified Schola Python client. D2 reports US3 as partially
complete until that integration is implemented.
