# US3: Connect to existing Python training tools

- **Owner:** Sanjay and Isaac
- **Status:** Complete on main
- **Last updated:** Nov. 25, 2026

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

- The gRPC server, RPC dispatch and transport tests merged in [PR #47](https://github.com/csc301-2026-f/20-AMD-Schola/pull/47) ([`87d77bb`](https://github.com/csc301-2026-f/20-AMD-Schola/commit/87d77bb)). `ScholaTrainingConnector` and `HostTrainingBackend` merged in [PR #59](https://github.com/csc301-2026-f/20-AMD-Schola/pull/59). The [US13 RaceTrack example](US13.md), merged in [PR #50](https://github.com/csc301-2026-f/20-AMD-Schola/pull/50), trains through this connector with Schola's Stable-Baselines3 trainer (`schola.sb3.VecEnv` over `GrpcProtocol`); its committed policy comes from a 650,000-step run. [US12](US12.md) records a Python client check over multiple episodes and the pending RLlib CLI run.
- `ScholaTrainingConnector` is the one node a user adds to a scene, like Unreal Schola's `AGymConnectorManager`. It trains every `ScholaEnvironment` in the scene through its own internal `ScholaTrainingHost` (US4) and blocks each physics frame until Python's next reset or step. `HostTrainingBackend` calls that host by method name, so the training extension does not link runtime C++ classes; spaces cross as Dictionaries rebuilt with `dictionary_to_space()` in `src/interop`, and points as Variants. Python drives the session: `StartGymConnector` → `set_autoreset_mode` (which first calls the host's `initialize_session()`, so an untrainable scene fails here and Python gets the error as its reply) → `RequestTrainingDefinition` → `define` → repeated `UpdateState` → `reset`/`step`, until Python's CLOSE ends the session. The connector then waits for a new session, as added in [PR #61](https://github.com/csc301-2026-f/20-AMD-Schola/pull/61). Usage is in the [Godot README](../../README.md#train-with-python).
- New tests:
  - `tests/unit/connector_loop_test.cpp` checks that `ConnectorLoop::ended_normally()` is true only after Python's CLOSE (not after a disconnect or timeout) and is cleared by the next `start()`.
  - `tests/integration/space_dictionary_test.gd` (4 tests) checks that `dictionary_to_space()` reads back exactly what `space_to_dictionary()` writes for every space type, including unbounded Box sides and nested Dicts, and rejects 12 kinds of malformed input with a message naming the field.
  - `tests/integration/training_connector_test.gd` (6 tests) uses the test-only `ScholaTrainingTestClient` (`tests/integration/native_training/`) to run start, define, reset, step and close through the real `HostTrainingBackend` and `ScholaTrainingHost`. It also checks that host errors reach Python unchanged, that a freed host fails cleanly, and that the connector node emits `training_finished(error)` when Python never connects. It needs the training extension built with `integration_tests=yes`, so it runs in CI on Linux with the committed gRPC package and is skipped locally otherwise.
- The connector loop, training messages, and gRPC boundary have been defined.
- The blocking `tick` model was retained and `poll_tick` was removed from the design.
- `poll_tick` and `Connector::poll_update` were removed from the code, as AMD recommended at partner meeting 5.
- [PR #35](https://github.com/csc301-2026-f/20-AMD-Schola/pull/35) introduced the packaging work on the D3 branch. The production tree includes committed Windows/Linux x86_64 gRPC packages, checksum/provenance verification, Protocol Buffer generation, and training-message conversions. Normal setup installs the committed package without compiling or downloading gRPC; explicit `--from-source` rebuilds remain available. The versions match Unreal Schola and await AMD confirmation.
- Space/point and training-message conversion tests are included in the `transport_tests` target and invoked by CI. These transport tests alone do not establish a completed trainer run; see the separate Python client check in [US12](US12.md).
- `GrpcConnector`, the server that Python's trainer connects to, is implemented. It answers the three calls Python makes: start (`StartGymConnector`), "what can I train?" (`RequestTrainingDefinition`), and reset or step (`UpdateState`). gRPC receives calls on its own threads, but only Godot's main thread may touch the game, so the connector hands each call to the main thread and waits for the answer.
- Connector waits are bounded by timeouts, and a Python disconnect ends the session. Messages up to 100 MB are allowed, so large observations such as camera images fit.
- Eight tests check the connector over a real network connection on one machine. A small C++ client plays Python and a fake game plays Godot. One test runs a whole session with two environments of two agents each and checks that every action and reward reaches the right agent. One sends an 8 MB observation. The rest break the session on purpose: Python never connects, goes silent, reports its own error, or hangs up mid-call; the game fails; or the port is already taken. Each ends with a clear error instead of hanging. The tests pass locally on Windows.
- The transport had only been built on Linux before. On Windows, a Windows macro named `ERROR` broke Schola's generated `ERROR` status value. Defining `NOGDI` for gRPC builds keeps that macro out.
- Fixes since: an infinite connector timeout waits forever instead of stopping at once ([PR #77](https://github.com/csc301-2026-f/20-AMD-Schola/pull/77)), a reply too large to send fails the session instead of being reported as sent ([PR #79](https://github.com/csc301-2026-f/20-AMD-Schola/pull/79)), and Box and MultiDiscrete values are copied into replies in bulk instead of one at a time ([PR #91](https://github.com/csc301-2026-f/20-AMD-Schola/pull/91)).
- The D3 demo uses the localhost JSON/TCP stand-in and a tabular learner. Its runner calls the native US4 host, but does not exercise the production gRPC connector.
