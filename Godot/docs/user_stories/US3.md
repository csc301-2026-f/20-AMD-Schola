# US3: Connect to existing Python training tools

- **Owner:** Sanjay and Isaac
- **Status:** Complete on main
- **Last updated:** November 26, 2026

## Story

As an ML practitioner, I want a Godot environment to connect to Schola's existing Python training tools so that I can train policies without maintaining a separate Godot-specific Python workflow.

## Acceptance criteria

- The Godot integration completes the connection and environment-definition exchange with the existing Python client.
- The integration uses Schola's existing protocol and gRPC services unless AMD approves an alternative.
- The transport implements `StartGymConnector`, `RequestTrainingDefinition`, and `UpdateState` from the existing Gym connector protocol.
- Python can discover the available environment, agents, observation spaces, and action spaces.
- The transport is isolated behind a core interface so the engine-independent code does not depend directly on gRPC.
- Connection failures and incompatible protocol data produce actionable errors instead of hanging the game or training process.

## Implementation

The gRPC transport merged in [PR #47](https://github.com/csc301-2026-f/20-AMD-Schola/pull/47), the scene connector/backend in [PR #59](https://github.com/csc301-2026-f/20-AMD-Schola/pull/59), and normal-session reconnection in [PR #61](https://github.com/csc301-2026-f/20-AMD-Schola/pull/61). A scene needs one `ScholaTrainingConnector`; it discovers the scene's environments through an internal production `ScholaTrainingHost`.

Python drives the shared `StartGymConnector`, `RequestTrainingDefinition`, and `UpdateState` services. The connector initializes the host, returns definitions, and executes reset/step requests on Godot's main thread. gRPC worker threads never touch the scene tree. `HostTrainingBackend` calls runtime methods by name and converts dictionary/Variant values at the extension boundary, so the training extension does not link runtime C++ classes.

Training uses the blocking request/response loop agreed with AMD. A physics frame waits for Python's next request; configured start/step timeouts bound waits. Normal CLOSE permits a fresh session on the same port, including RLlib's discovery-then-training sequence. Unexpected disconnects, host failures, malformed data, and oversized replies fail the session with contextual errors. PRs #77 and #79 cover infinite timeout configuration and reply-size failures; #91 reduces reply copying. Messages up to 100 MB are supported.

Windows/Linux x86_64 gRPC packages are committed with checksums, licenses, and provenance. Setup verifies and installs them without compiling or downloading; `--from-source` is an explicit rebuild operation. The versions match Unreal Schola and await AMD confirmation. SCons generates bindings from the shared `Proto/` definitions.

## Trainer and test evidence

The [RaceTrack example](../../examples/race_track/README.md), merged in PR #50, trains Stable-Baselines3 PPO through Schola's existing wrapper and the production connector, exports ONNX, and runs the learned policy without Python. The current Windows check completed 600 smoke steps with 5 episode endings, then 1,024 PPO steps and ONNX export. The exported model ran for 120 native physics frames after training exited.

[US12](US12.md) records the earlier Windows RLlib review and the current 4,096-step, 299-episode rerun with 2 heterogeneous policies. The additional stacked-observation run completed 4,096 steps and 288 episodes. See the [verification record](../verification.md) for commands, results, and their scope.

Automated coverage includes the connector loop's normal-close state, space/point and training-message conversions, real localhost RPC sessions, and Godot backend integration. Tests exercise multiple environments and agents, action/result routing, an 8 MB observation, host-error propagation, missing Python, silent/disconnected clients, occupied ports, and reconnecting after a normal close. The current Windows transport suite passed 23 cases; both native extensions and the full Godot integration suite also passed. Training-specific integration helpers require `integration_tests=yes`.

The earlier D2/D3 JSON/TCP stand-ins belong to their historical demos. Current source training uses this production gRPC path. Setup, timeout configuration, and training-only scene guidance are in the [developer README](../../README.md#train-with-python).
