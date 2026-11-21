# US3: Connect to existing Python training tools

- **Owner:** Sanjay and Isaac
- **Status:** Transport and scene connector merged; trainer validation and reconnect follow-up open
- **Last updated:** Nov. 21, 2026

## Story

As an ML practitioner, I want a Godot environment to connect to Schola's existing Python training tools so that I can train policies without maintaining a separate Godot-specific Python workflow.

## Acceptance criteria

- The Godot integration completes the connection and environment-definition exchange with the existing Python client.
- The integration uses Schola's existing protocol and gRPC services unless AMD approves an alternative.
- The transport implements `StartGymConnector`, `RequestTrainingDefinition`, and `UpdateState` from the existing Gym connector protocol.
- Python can discover the available environment, agents, observation spaces, and action spaces.
- The transport is isolated behind a core interface so the engine-independent code does not depend directly on gRPC.
- Connection failures and incompatible protocol data produce actionable errors instead of hanging the game or training process.

## Progress

- The gRPC server and transport tests merged in [PR #47](https://github.com/csc301-2026-f/20-AMD-Schola/pull/47). `ScholaTrainingConnector` and `HostTrainingBackend` then merged in [PR #59](https://github.com/csc301-2026-f/20-AMD-Schola/pull/59) on Nov. 19. Both transport and the scene-facing connector are on main.
- A scene adds `ScholaTrainingConnector`, which creates an internal `ScholaTrainingHost` and routes Python's start, definition, reset, step, and close requests through the production lifecycle. Only the Godot main thread accesses scene objects; gRPC calls cross the transport boundary as owned values. See [Train with Python](../../README.md#train-with-python).
- Native connector-loop tests distinguish normal close from timeout/disconnect. Godot integration tests cover dictionary space conversion, a session through the real backend and host, host failures, and connection timeout. Network tests cover multi-environment routing, large observations, disconnects and backend failures. These tests do not by themselves establish a real Python trainer run.
- The committed Windows/Linux gRPC packages, offline installer, generated bindings and protobuf conversion tests are on main. No separate Godot wire protocol is introduced.
- Draft [PR #61](https://github.com/csc301-2026-f/20-AMD-Schola/pull/61) adds reconnect support needed by `schola rllib train`: Python connects once for discovery and again for training. Its branch reports five random-action episodes through Schola's RLlib environment classes on macOS, but the actual RLlib CLI training run on Windows/Linux remains pending. These changes and evidence are not yet on main.
- Draft [PR #50](https://github.com/csc301-2026-f/20-AMD-Schola/pull/50) includes a production SB3 training/export workflow for RaceTrack. Its branch reports a trained policy and inference scores; clean-checkout reproduction and retraining remain open under [US13](US13.md). This is branch evidence, not validation of unchanged main.
