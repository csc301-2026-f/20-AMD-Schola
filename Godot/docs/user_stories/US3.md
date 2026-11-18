# US3: Connect to existing Python training tools

- **Owner:** Sanjay and Isaac
- **Status:** gRPC core merged; scene connector in progress
- **Last updated:** Nov. 18, 2026

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

- The Nov. 18 live branch/PR review confirms the scene-connector branch is still at `2663948`, with no corresponding PR. The merged transport core and unmerged scene connector remain separate milestones; US3 is not complete.

- The gRPC server, RPC dispatch and transport tests merged in [PR #47](https://github.com/csc301-2026-f/20-AMD-Schola/pull/47) ([`87d77bb`](https://github.com/csc301-2026-f/20-AMD-Schola/commit/87d77bb)). `ScholaTrainingConnector` and `HostTrainingBackend` have an implementation on `Isaac-Sanjay/us3/godot-training-connector` ([`2663948`](https://github.com/csc301-2026-f/20-AMD-Schola/commit/2663948)). The scene connector still needs to land on main, and a full run with Schola’s Python trainer remains unverified in the reviewed history.
- The connector loop, training messages, and gRPC boundary have been defined.
- The blocking `tick` model was retained and `poll_tick` was removed from the design.
- `poll_tick` and `Connector::poll_update` were removed from the code, as AMD recommended at partner meeting 5.
- [PR #35](https://github.com/csc301-2026-f/20-AMD-Schola/pull/35) introduced the packaging work on the D3 branch. The production tree includes committed Windows/Linux x86_64 gRPC packages, checksum/provenance verification, Protocol Buffer generation, and training-message conversions. Normal setup installs the committed package without compiling or downloading gRPC; explicit `--from-source` rebuilds remain available. The versions match Unreal Schola and await AMD confirmation.
- Space/point and training-message conversion tests are included in the `transport_tests` target and invoked by CI. These test files do not establish a completed Python-to-Godot transport session.
- `GrpcConnector`, the server that Python's trainer connects to, is implemented. It answers the three calls Python makes: start (`StartGymConnector`), "what can I train?" (`RequestTrainingDefinition`), and reset or step (`UpdateState`). gRPC receives calls on its own threads, but only Godot's main thread may touch the game, so the connector hands each call to the main thread and waits for the answer.
- Connector waits are bounded by timeouts, and a Python disconnect ends the session. Messages up to 100 MB are allowed, so large observations such as camera images fit.
- Eight tests check the connector over a real network connection on one machine. A small C++ client plays Python and a fake game plays Godot. One test runs a whole session with two environments of two agents each and checks that every action and reward reaches the right agent. One sends an 8 MB observation. The rest break the session on purpose: Python never connects, goes silent, reports its own error, or hangs up mid-call; the game fails; or the port is already taken. Each ends with a clear error instead of hanging. The tests pass locally on Windows.
- The transport had only been built on Linux before. On Windows, a Windows macro named `ERROR` broke Schola's generated `ERROR` status value. Defining `NOGDI` for gRPC builds keeps that macro out.
- The D3 demo uses the localhost JSON/TCP stand-in and a tabular learner. Its runner calls the native US4 host, but does not exercise the production gRPC connector.
