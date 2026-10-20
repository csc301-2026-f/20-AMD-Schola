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

One step reports an observation, reward, `terminated` state, `truncated` state,
and episode/step identifiers to the backend. The backend returns one action. The
specific local transport is a US3 implementation decision and must remain behind
the connector interface.

## Telemetry contract

The runtime panel will display connection state, control mode, episode number,
step number, cumulative reward, latest observation, latest action, and terminal
result. The panel is a visual consumer of plugin state; it must not perform
lifecycle coordination or transport work.
