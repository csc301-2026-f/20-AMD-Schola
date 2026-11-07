# US3: Connect to existing Python training tools

- **Owner:** Sanjay and Isaac
- **Status:** In progress
- **Last updated:** Nov. 6, 2026

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

- The connector loop, training messages, and gRPC boundary have been defined.
- The blocking `tick` model was retained and `poll_tick` was removed from the design.
- `poll_tick` and `Connector::poll_update` were removed from the code, as AMD recommended at partner meeting 5.
- PR #35 adds committed Windows/Linux x86_64 gRPC packages, checksum/provenance verification, Protocol Buffer generation, and training-message conversions. Normal setup installs the committed package without compiling or downloading gRPC; explicit `--from-source` rebuilds remain available. The versions match Unreal Schola and await AMD confirmation.
- Space/point and training-message conversion tests are included in the `transport_tests` target and invoked by CI. These test files do not establish a completed Python-to-Godot transport session.
- `GrpcConnector`, the server that Python's trainer connects to, is implemented. It answers the three calls Python makes: start (`StartGymConnector`), "what can I train?" (`RequestTrainingDefinition`), and reset or step (`UpdateState`). gRPC receives calls on its own threads, but only Godot's main thread may touch the game, so the connector hands each call to the main thread and waits for the answer.
- The connector never hangs. Every wait has a timeout, and a Python disconnect ends the session. Messages up to 100 MB are allowed, so large observations such as camera images fit.
- Eight tests check the connector over a real network connection on one machine. A small C++ client plays Python and a fake game plays Godot. One test runs a whole session with two environments of two agents each and checks that every action and reward reaches the right agent. One sends an 8 MB observation. The rest break the session on purpose: Python never connects, goes silent, reports its own error, or hangs up mid-call; the game fails; or the port is already taken. Each ends with a clear error instead of hanging. The tests pass locally on Windows.
- The transport had only been built on Linux before. On Windows, a Windows macro named `ERROR` broke Schola's generated `ERROR` status value. Defining `NOGDI` for gRPC builds keeps that macro out.
- Still to do: the Godot node that runs the connector in a scene (`ScholaTrainingConnector`) and its link to the training host (`HostTrainingBackend`), a test with Schola's real Python client, and a full training run in a Godot scene.
- The D3 demo uses the localhost JSON/TCP stand-in and a tabular learner. Its runner calls the native US4 host, but does not exercise the production gRPC connector.
