# AMD Schola Partner Meeting 7

## Meeting details

- **Date:** Nov. 6, 2026
- **Time:** 11:00–11:40 a.m.
- **Location:** Microsoft Teams
- **Minutes prepared by:** Sanjay Ram
- **Minutes source:** Granola notes and meeting transcript

## Attendees

### AMD

- Alexander Cann -- MTS @ AMD

### CSC301 team

- Sanjay Ram
- Jimmy Zhu
- Vansh Sehrawat
- Bohdan Zmeul
- Isaac Tilahun (joined partway through)

### Absent

- Shahyar Anfaz

## Progress review

### US1: Define a reinforcement-learning environment

- Sanjay took over US1 this week and completed the environment adapter, building on Isaac's agent adapter.
- The environment adapter initializes all agents in scene-tree order.
- Reset and step call each agent's bound `define`, `observe`, and `act` methods through the agent adapter.
- Integration tests for the environment adapter remain. They were blocked by dependencies that were not yet on the branch and are targeted for the next meeting.

### US2: Declare observation and action spaces

- US2 is complete. Jimmy is waiting for the new user stories to be approved before starting new work.

### US3: Connect to existing Python training tools

- The gRPC and Protobuf build now works on Linux, Windows, and macOS.
- The connector loop orchestrates messages between Godot and the Python trainer and runs the training session on Godot's main thread.
- Conversions from Protobuf messages to Schola's internal types are implemented.
- Isaac is taking over the concrete gRPC connector from Sanjay's work. Part of it is written.
- Both sides of the connector can be mocked for tests and benchmarks.
- Once the connector is complete, the team will run end-to-end tests and an actual training run.

### US4: Execute the episode lifecycle

- Not presented because Shahyar was absent.

### US5: Configure Schola through Godot-native tools

- The four step callbacks were replaced by `get_step_result`, which returns the reward (required) and optional terminated, truncated, and extra-info values.
- Reset remains a separate callback.
- The built-in step-limit Inspector property was removed. Users now write their own truncation and termination logic.
- The `ScholaAgent` Inspector sets the agent ID, agent type, and observation and action spaces, with hints explaining each field. Nested dictionary spaces can be built in the Inspector.
- Alex noted that the Inspector works well for simple and discrete spaces but becomes tedious for large Box spaces. Even a small camera image, such as 32×30, needs hundreds of low and high values.
- Alex suggested a code-based way to define spaces in addition to the Inspector:
  - Unreal moved from Inspector-defined spaces to a callback for this reason.
  - A static property, however, lets tooling hook into the definition, for example to generate derived types, which the callback approach loses.
  - Coding agents make it practical to maintain many simple space types with round-trip and sanity tests.
- New space types currently must be added to the Inspector variant manually; users cannot register custom types.
- Each agent shows its own configuration warnings, and the environment node aggregates warnings from all of its agents.
- Alex cautioned that aggregating every warning may become "warning soup" when several agents are misconfigured. One warning per agent or a short summary pointing to the affected agents is an alternative, at the cost of less detail.

### US7: Run and ship an ONNX policy

- At D2, core inference worked: `OnnxPolicy` loaded models through ONNX Runtime, and `PolicyState` kept each agent's memory between steps.
- With US1 and US2 in place, the inference stepper now runs the full loop every physics frame: it gathers observations, runs the model, and applies actions. Developers add a policy to an agent in the Inspector.
- The policy takes its spaces from the agent and validates the model against them. A missing or mismatched model produces a clear error.
- Tests pass on Windows and in Linux CI, and a guide covers setup and export.
- Two crashes were fixed: changing the policy during a step, and removing an agent during a step.
- A bug where the previous model kept running silently after the model path changed was fixed.

### CI improvements

- CI had been slow, taking about 30 minutes per run. Shahyar and Sanjay added build caching.

## CI pipeline discussion

- Sanjay asked how the Unreal CI avoids rebuilding gRPC C++ dependencies on every run.
- Unreal keeps dependencies in the repository through Git LFS. Its private CI runs behind a corporate firewall where LFS alone did not work well, so it adds separate caching.
- The Unreal test suite is split by change type: Python changes run Python tests, Unreal changes run Unreal tests, and Protobuf changes run both.
- Builds are reused as much as possible during testing and run in parallel across Linux and Windows machines.
- A full Unreal CI run takes close to an hour, mostly spent on nine builds: six on Windows and three on Linux.
- The Windows builds include checking that the plugin packages in distributable mode, because some errors have only appeared during packaging.
- Python tests run on GitHub Actions runners. Anything that executes Unreal runs on self-hosted runners.
- The Godot CI currently tests only Linux, by default rather than by deliberate choice.
- Alex recommended testing Windows as well, because the per-OS gRPC builds do not behave the same.
- If only one OS is tested, it should be Windows, since games are mostly played on Windows, unless Linux is dramatically faster.

## Upcoming user stories

The team presented the new user stories and asked for feedback on scope and priority.

### MVP (highest priority)

- **US8: Sensors and actuators.** Reusable nodes, such as raycast sensors and movement actuators, replace hand-written `observe` and `act` code, mirroring Unreal's sensor and actuator interfaces.
- **US12: Multi-agent training.** Much of the Godot side exists already. The remaining work is proving in real training, with at least two agents, that every action and reward reaches the correct agent.
- **US13: Production example.** Uses the real gRPC path and a Schola-supported trainer, reports a metric showing the agent learned, and runs the exported policy in Godot with Python closed. It also serves as the starting point for new users and is required for D4.

### Stretch goals

- **US9: Test an environment without Python.** Similar to Unreal's manual connector. Developers can reset an environment, submit actions, and read observations, rewards, and episode endings from GDScript or automated tests, using production code paths and the same errors as real training.
- **US10: Observation stacking.** Matches Unreal's Box and Dict stackers. Gives the policy a short history without a recurrent model, which is useful for Stable Baselines3, since Schola's recurrent option goes through RLlib.
- **US11: Camera sensor.** Builds on the US8 sensor model. Developers set width, height, and color channels in the Inspector, and the pixel layout and normalization will be documented.
- **US14: Read the state sequence length from the model.** Reads the maximum state sequence length from ONNX metadata for inference. Work starts once Alex's metadata export PR lands.

### Feedback

- Alex approved the proposed user stories.
- Alex noted that US10 interacts closely with how spaces are defined, because stackers change the space sent to the trainer.
- Stackers should not be hardcoded. An agent should hold a generic list of observation adapters or wrappers, so other transforms, such as normalization, fit the same mechanism. In base Schola, stackers are their own optional type used only for convenience.
- Alex asked whether the team had run a round-trip test that trains, exports, and runs an agent. US13 will cover this in depth; small tests were done as part of the course demos.

## Python CLI flags for Godot

- Schola's Python CLI has Unreal-specific options, such as headless mode and unlimited-FPS benchmarking. Headless mode can raise Unreal's steps per second by about 10×.
- Passing these Unreal flags to Godot does nothing at best and may crash the process.
- Alex suggested adding a layer that maps user intent, such as headless mode or an FPS setting, to the flags the Godot process expects. This can be delivered as a PR or as Godot-specific changes in a custom version of the Python package.
- This is expected to be a minor change.

## Decisions

- Approve the new user stories, with US8, US12, and US13 as the MVP and US9, US10, US11, and US14 as stretch goals.
- Design US10 stackers as generic observation adapters rather than a stacking-specific type.
- Test Godot CI on Windows as well as Linux. If only one OS is tested, prefer Windows.
- Present an end-to-end demo at the next meeting.

## Action items

| Owner | Action | Status at meeting end |
|---|---|---|
| Sanjay | Complete the US1 environment-adapter integration tests by the next meeting. | Open |
| Sanjay | Adapt the Python CLI flags, such as headless mode and the FPS cap, for Godot. | Open |
| Isaac | Finish the US3 gRPC connector, then run end-to-end tests. | Open |
| Vansh | Look into a code-based space-definition path and simpler warning aggregation for US5. | Open |
| Alex | Open the PR that adds ONNX metadata to policy export and notify the team. | Open |
| Team | Prepare an end-to-end demo for the next meeting and update Alex in the group chat if plans change. | Open |

## Logistics

- Isaac joined partway through because of another meeting.
- Shahyar was absent, so the US4 and CI-improvement updates were not presented in depth.
- Alex will be away at a conference the following week but still expects a demo at the next meeting.
- The meeting ended about 20 minutes early.
