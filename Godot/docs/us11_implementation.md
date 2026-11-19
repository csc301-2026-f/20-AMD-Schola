# US11 completion plan

- Owners: Bohdan and Vansh
- Updated: Nov. 19, 2026
- Status: camera sensors exist; example and workflow validation pending

## Setup

- Reuse US8 camera sensors, Box spaces, the production host/connector, and ONNX APIs.
- Add `Godot/examples/camera_observation/` with separate scene, controller,
  environment script, and README.
- Use RGB 64x64: float32 Box `[3,64,64]`, CHW order, bounds `[0,1]`.
- Match the existing fixture: `00000000:Camera` observation and
  `00000000:Rotation` action, Box `[1]` bounded by `[-10,10]`.
- Show the captured image and a short status summary. The fixture is untrained.
- Run manual control and inference separately. Keep existing depth tests.
- Start with Windows Compatibility rendering. Real capture requires rendering;
  fake-camera headless tests do not prove real-camera training works.

## Implementation steps

1. Build the rendered example and verify manual reset/step through the host.
2. Resolve rendering/connector scheduling with Sanjay and Isaac using the
   experiment below. Confirm the US3 revision before integrating branches.
3. Feed real camera pixels through the exported policy and rotation actuator.
4. Add missing configuration checks and tests for invalid viewports, dimensions,
   channels, unavailable pixels, changed settings, repeated capture, and resets.
5. Run a production Python training smoke test across multiple episodes with
   optimizer updates. Verify image layout and normalization.
6. Run native inference, headless integration, and rendered camera tests using
   the Godot README. Check formatting and update docs with actual results.

The current ONNX fixture and comparison test check compatibility, not learning.
Training remains pending until real-camera integration passes. Learned-performance
benchmarking belongs to US13; agree any scope change with the story owners.
Follow the development contract and preserve frozen demos and Unreal files.

## Rendering/connector scheduling experiment

**Decision pending.** The inspected US3 revision, `c7230858`, starts and ticks the
blocking connector in `_physics_process()`. The sensor reads the latest completed
frame. Host reset/step calls cannot await rendering between their callbacks.
This is a scheduling risk; a deadlock has not been demonstrated.

1. Create a 64x64 viewport whose visible marker changes on each reset and action.
   Drive it through the production connector with a deterministic Python client.
2. Log request, episode, action, physics frame, completed-render count, and sampled
   pixels. Check pixels against the expected scene state.
3. Test startup, explicit reset, autoresets, fast/slow requests, and disconnects.
4. Agree which module schedules rendering, the supported action-to-image delay,
   and bounded failure/shutdown behavior. Record the decision and a regression
   test before making a focused cross-story change.

Startup and reset images must match the intended scene state. Waiting before
`reset()` alone is insufficient: `_reset_episode()` can change the scene afterward.
Verify that rendering progresses between requests and explain any reused frames.

Keep Godot access on the main thread. Do not busy-wait for rendering, await inside
the synchronous `_observe()` hook, or restore the rejected polling model.
