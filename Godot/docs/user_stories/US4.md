# US4: Execute the episode lifecycle

- **Owner:** Shahyar
- **Status:** Implemented; end-to-end testing blocked by US1
- **Last updated:** Oct. 30, 2026

## Story

As an ML practitioner, I want Schola to coordinate observations, actions, rewards, terminal states, and resets so that training proceeds correctly across complete episodes.

## Acceptance criteria

- For each step, Godot supplies an observation and accepts a compatible action from Python.
- Each step returns the resulting observation, reward, and termination or truncation state.
- Reset restores the demonstration environment to a valid initial state and returns an initial observation.
- The connector supports the existing disabled, same-step, and next-step auto-reset modes with the same externally observable behavior as Schola's Python API.
- The connector can coordinate more than one environment in a running scene.
- An integration test completes multiple episodes without lifecycle deadlock or state leakage between episodes.

## Progress

- `ScholaTrainingHost` is fully implemented. It discovers environment nodes and constructs one lifecycle per environment.
- Session initialization is atomic: a failure does not expose a partially initialized session.
- Godot-facing host operations enforce main-thread execution.
- If an environment node disappears, or if any coordinator or environment operation fails, the entire session closes while preserving the original error.
- Definitions, states, and step results are transactional; failed operations do not publish partial output.
- `_exit_tree` performs clean shutdown.
- End-to-end testing is blocked until the US1 environment adapter is implemented.
