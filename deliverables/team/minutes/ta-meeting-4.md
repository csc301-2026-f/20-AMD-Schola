# TA Meeting 4

## Meeting details

- **Date:** Nov 5, 2026
- **Time:** 8:00 p.m.–8:30 p.m.
- **Location:** Zoom
- **Minutes prepared by:** Sanjay Ram
- **Minutes source:** Granola notes and meeting transcript

## Attendees

### TA

- Salman Sayeed

### CSC301 team

- Guneev Pannu
- Sanjay Ram
- Bohdan Zmeul
- Vansh Sehrawat
- Shahyar Anfaz
- Isaac Tilahun
- Jimmy Zhu

## Meeting objectives

- Present Deliverable 3 progress for each user story.
- Demonstrate the updated grid-world training and inference demo.
- Collect feedback for the next presentation.

## User-story progress

### US1: Define a reinforcement-learning environment

- Isaac implemented the `ScholaAgent` adapter and the bound methods that connect it to Godot.
- Sanjay implemented the `ScholaEnvironment` adapter, which uses the agent adapter to drive each agent.
- The environment adapter initializes agents through a depth-first search of the scene tree.
- Reset and step, the operations reinforcement-learning training depends on, are implemented.
- US1 is about 95% complete. Integration tests for the environment remain.

### US2: Declare observation and action spaces

- US2 is complete. Box, discrete, multi-discrete, and multi-binary spaces and points are implemented and covered by round-trip tests.
- A diagram showed agent spaces and observations flowing to Python and actions returning to the agent's `act` method.
- The team has proposed new user stories, US8–US13, and is waiting for AMD approval before starting them.

### US3: Connect to existing Python training tools

- The goal of US3 is to train Godot games with the same Python tools Schola uses for Unreal Engine.
- Godot does not include gRPC, so the team builds gRPC and Protobuf itself for Linux, Windows, and macOS, using the same versions as Schola for Unreal.
- The connector loop runs Python's requests, such as actions and resets, in the game once per frame. Keeping requests in order prevents a late action from receiving the reward for the wrong observation.
- Protobuf conversions translate Python's messages into Schola's C++ types and reject invalid data.
- The gRPC connector, which lets Python connect to the running Godot game, is mostly written. Isaac is wiring it to the existing work from Guneev and Sanjay.
- Sanjay and Shahyar added caching to CI, significantly reducing build time for pull requests.
- The remaining work is mostly testing.

### US4: Execute the episode lifecycle

- US4 is complete. New since D2 are coordination of multiple environments in one running scene and integration testing with the other user stories, verified end to end across US1–US5.
- The environment coordinator and lifecycles are engine-independent C++ and reach Godot scene-tree nodes through adapters.
- `ScholaTrainingHost` owns the coordinators and discovers the adapters. Schola and Python communicate through gRPC.
- Verification includes 40 core tests and 10+ host integration test cases.
- The core tests cover lifecycle transitions, all reset modes, repeated episodes, state isolation, episode leakage, and main-thread enforcement.
- The host integration tests incorporate behavior from the other user stories.
- Changes since D2:
  - Session initialization is atomic.
  - The training host requires all scene-tree access to happen on the main thread and rejects other calls.
  - Environment IDs are assigned at initialization and stay fixed, following partner feedback.
  - An error in any lifecycle closes all lifecycles instead of continuing training with undefined state.
  - Outputs are transactional, so failed operations do not complete half an action.
  - `close` is idempotent, partial initialization is handled safely, and `_exit_tree` frees all memory the host owns.
  - The ABI boundary for gRPC communication is defined to be Godot-compatible, because `ScholaTrainingHost` lives on the Godot side.

### US5: Configure Schola through Godot-native tools

- US5 is fully implemented and merged into `main`.
- Four step callbacks were combined into one `get_step_result` function that returns all values together. Separate functions could be called in the wrong order; one function enforces a consistent order.
- `reset_episode` stays separate because it does not belong in every step.
- The built-in step-limit option was removed, so users implement whichever truncation style they prefer.
- The partner approved both changes.
- The `ScholaAgent` Inspector shows agent ID, agent type, observation space, and action space, with explanations, defaults, and hints.
- The agent ID is optional and falls back to the node name. Setting one helps when duplicating environments.
- The agent type is optional and lets multiple agents share a policy, such as many enemies sharing an enemy policy.
- Inspector warnings report missing implementations such as `get_step_result`, wrong return values, duplicate agent IDs within an environment, missing spaces, and missing behavior hooks. They refresh in real time as the scene tree changes.
- Additional bug fixes and tests covered how the Inspector UI interacts with the plugin.

### US7: Run and ship an ONNX policy

- At D2, the core of inference worked: `OnnxPolicy` ran models through ONNX Runtime, `PolicyState` held each agent's memory between steps, and a trained policy ran with Python closed. The automatic stepper and its connection to agents were missing.
- With US1 and US2 in place, the inference stepper now runs the full loop every physics frame: it gets the agent's observation, runs the model, and applies the action. Developers add a policy to their agents in the Inspector.
- Outputs from real exported models match Python.
- An exported game runs without Python and without the training add-on.
- Tests pass on Windows and in Linux CI.
- Testing with real trained models found several bugs, all fixed:
  - Trained agents often output actions slightly past their limits, which were rejected and could stop an agent completely. These actions are now clamped to the limits.
  - The stepper crashed when the policy changed during a step and when an agent was removed during a step.
  - The old model kept running silently after the model path changed.
- The remaining work is testing macOS exports and adding macOS to CI.

## CI/CD improvements

- CI first checks whether a change affects Godot. If it does, three jobs run in parallel: clang-format, the Linux build with native tests, and Windows dependency verification.
- The Linux build uploads the extension for the Godot smoke and integration tests, and a required check confirms that every job passed.
- The Linux build, about 2.5 minutes in the run shown, was the main bottleneck.
- godot-cpp takes about 8 minutes to compile. SCons caching now reuses compiled objects when their inputs are unchanged, and the integration-test flag no longer invalidates them.
- The gRPC and Protobuf stack takes over 30 minutes to compile. Prebuilt Linux and Windows packages are now stored through Git LFS, and CI verifies and installs them instead of compiling. This works even when the Actions cache is empty.
- Comparing runs before and after the changes showed a 93% reduction in build time.

## Demonstration

- Guneev presented the grid-world demo, in which a blue agent learns to reach a green square.
- New since D2:
  - A map editor places the goal and obstacles and saves the layout.
  - Parallel training runs many instances at once; 12 were shown.
  - A chart shows reward during training.
- The interface still shows episode, step, reward, outcome, action, observation, and trainer state.
- During training, the reward rose. Stepping with the trained policy, the agent reliably reached the goal.

## Feedback

- Salman praised the CI/CD work, especially the 93% build-time reduction.
- Salman also praised the demo improvements, especially parallel training and map editing.
- Salman asked how transactional outputs behave when a training step fails partway, including what the visualizer shows.
  - Shahyar explained that if one agent attempts an illegal action, such as walking off the board, the whole step fails for every agent rather than leaving that agent in an undefined state.
  - The retry policy after a failed step was not confirmed.
- Salman asked whether multiple agents in one environment had been tested in the visualizer.
  - Multi-agent environments are believed to be implemented through US1 but are not in the demo yet, because the team is still making them work with parallel training.
- Salman asked whether the visualizer is part of the extension.
  - The grid-world scenario exists only for the course demo. The parallel-training tooling is part of the tool.
- Salman recommended clarifying transactional-output behavior and handling its corner cases, and otherwise found the presentation strong.

## Logistics

- Starting the following week, meetings move to Thursdays at 8:00 p.m., replacing the 8:30 p.m. slot.
- This was the last demo presented directly to Salman. D4 is expected to be a final presentation, but the format is not confirmed.
- Future meetings will be discussion and tutorial meetings in the same Thursday 8:00 p.m. slot.

## Action items

| Owner | Action | Status at meeting end |
|---|---|---|
| Sanjay | Write integration tests for the US1 environment adapter. | Open |
| Isaac | Finish wiring the US3 gRPC connector, then test it. | Open |
| Bohdan | Test macOS exports and add macOS to CI. | Open |
| Team | Clarify transactional-output behavior and its corner cases, including the retry policy after a failed step. | Open |
| Team | Pick up the new user stories, US8–US13, once AMD approves them. | Open |
