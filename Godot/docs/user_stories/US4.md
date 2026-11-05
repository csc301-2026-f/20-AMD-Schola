# US4: Execute the episode lifecycle

- **Owner:** Shahyar
- **Status:** Complete
- **Last updated:** Nov. 4, 2026

## Story

As an ML practitioner, I want Schola to coordinate observations, actions, rewards, terminal states, and resets so that training proceeds correctly across complete episodes.

## Acceptance criteria

- For each step, the lifecycle accepts actions through its core API or Godot host and returns the resulting observations.
- Each step returns the resulting observation, reward, and termination or truncation state.
- Reset restores the demonstration environment to a valid initial state and returns an initial observation.
- The coordinator supports the existing disabled, same-step, and next-step auto-reset modes with the same externally observable behavior as Schola's Python API.
- The host can coordinate more than one environment in a running scene.
- An integration test completes multiple episodes without lifecycle deadlock or state leakage between episodes.

## Progress

- `ScholaTrainingHost` is fully implemented. It discovers environment nodes and constructs one lifecycle per environment.
- Session initialization is atomic: a failure does not expose a partially initialized session.
- Godot-facing host operations enforce main-thread execution.
- If an environment node disappears, or if any coordinator or environment operation fails, the entire session closes while preserving the original error.
- Definitions, states, and step results are transactional; failed operations do not publish partial output.
- `_exit_tree` performs clean shutdown.
- The Godot host integration suite runs against the native US1 adapter and covers multiple environments, repeated episodes, all three autoreset modes, and session failure handling.
- Reset requests validate environment IDs, settings, signed 32-bit seeds, and string options before any environment resets. Invalid requests leave the session usable.

## Ownership boundary

US4 owns episode coordination and the Godot training host. Python client connectivity, gRPC transport, and Python-to-Godot integration testing belong to US3 and do not block US4 completion.
