# Schola D2 training-workflow demo

This is the D2 demonstration skeleton. It will show a single Godot environment
exchanging observations, actions, rewards, and episode state with a local Python
client, followed by optional local execution of a saved policy artifact.

The project is intentionally incomplete while the user-story implementations are
being merged. Its scene tree, telemetry panel, and integration contract establish
the shared target for those branches without duplicating plugin functionality.

## Open the skeleton

Open `Godot/demos/d2_training_workflow/project.godot` in Godot 4.7. The scene is a
layout placeholder; it does not yet run a Schola training session.

## Planned demo contract

- Observation: `Box(4)` containing `[agent_x, agent_y, goal_dx, goal_dy]`.
- Action: `Discrete(4)` containing the arena movement choices up, down, left, and
  right.
- Backend: a local Python reference client for D2 only.

These values are example choices for this scene. They do not constrain other
projects using the Schola plugin. See [integration_contract.md](integration_contract.md)
for ownership and integration details.
