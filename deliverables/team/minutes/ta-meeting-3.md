# TA Meeting 3

## Meeting details

- **Date:** Oct 22, 2026
- **Time:** 8:00 p.m.–8:30 p.m.
- **Location:** Zoom
- **Minutes prepared by:** Sanjay Ram / Shahyar Anfaz
- **Minutes source:** Shared Granola notes

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

- Demonstrate the current Godot reinforcement-learning workflow.
- Review progress and remaining work for each user story.
- Collect feedback on the presentation and technical direction.

## User-story progress

### US1: Engine-independent C++ environment API

- The agent API defines the action and observation spaces and the `observe` and `act` operations.
- The environment API supports initialization, reset, stepping, and agent discovery.
- The core structs cover interaction definitions, reset settings, agent state, and agent IDs.
- A grid-world test validates the lifecycle independently of Godot.
- The next step is connecting the engine-independent API to Godot.

### US2: Observation and action spaces

- Box, discrete, and multi-binary spaces were mostly complete.
- A few edge cases remained because GDScript and C++ handle some values differently.

### US3: Connector loop

- The main loop handles the handshake, tick and poll operations, step, reset, and close.
- The gRPC connector and training-message types were implemented.
- The Deliverable 2 demonstration used a local GDScript stub instead of the real gRPC transport.
- The real gRPC connector is planned for the next deliverable.

### US4: Episode lifecycle management

- The design consists of the lifecycle, lifecycle coordinator, and `ScholaTrainingHost` components.
- The lifecycle and coordinator were complete, with every automatic-reset mode tested.
- The remaining work was `ScholaTrainingHost` scene discovery and agent initialization.

### US5: Godot-facing scene-node API

- Native `ScholaEnvironment` and `ScholaAgent` nodes replaced the Deliverable 2 stand-ins.
- The Inspector exposes IDs, policy types, and observation and action-space resources.
- Invalid configurations, including missing spaces and duplicate agent IDs, are reported immediately.
- The Deliverable 2 architecture still required a full test pass before merging into `main`.

### US7: ONNX policy inference

- Policies can be loaded and validated against agent spaces with clear error messages.
- The observe-infer-act loop was implemented and tested; the agent consistently reached the goal.
- Only ONNX Runtime ships with the add-on. Training and networking dependencies are excluded.
- The remaining work was building the export workflow and running an end-to-end packaged test.

## Demonstration

- The team trained the grid-world agent live. Its behavior began randomly and improved as the reward graph climbed.
- A pretrained model consistently reached the goal with a nearly constant reward.
- The interface displayed observation spaces, episode and step counts, rewards, and runtime states.

## Feedback

- The presentation exceeded its 15-minute limit.
- Salman recommended using one diagram per user story to show completed and remaining work instead of reviewing functions individually.
- Salman highlighted the learning graph and live parameter display as particularly strong parts of the demonstration.
- Multiple agents with different observation and action spaces can share an environment, and multiple environments can run simultaneously.
- The Godot developer controls environment structure, including curricula that move an agent between progressively varied maps.

## Action items

| Owner   | Action                                                                                        | Status at meeting end |
|---------|-----------------------------------------------------------------------------------------------|-----------------------|
| Sanjay  | Replace the local GDScript stub with the real gRPC connector.                                 | Open                  |
| Shahyar | Complete `ScholaTrainingHost` scene discovery and lifecycle initialization.                   | Open                  |
| Vansh   | Run the full test suite for the native US5 scene-node architecture and merge it into `main`.  | Open                  |
| Bohdan  | Build and test ONNX export end to end, including loading the policy from packaged game files. | Open                  |
| Team    | Shorten future presentations and use one progress diagram per user story.                     | Open                  |
