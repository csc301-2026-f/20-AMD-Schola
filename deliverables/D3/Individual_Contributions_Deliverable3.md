# Schola for Godot - Individual Contributions (D3)

> For each team member: name, role, and specific contributions. Be precise about what you did, not how much you wrote.

## Shahyar Anfaz - Native lifecycle, integration, and CI/CD

- Implemented the native `ScholaTrainingHost`, connecting scene discovery, environment definitions, reset, step, autoreset, and close to the production lifecycle. Added Godot integration coverage for multiple environments, repeated episodes, validation, and failure behavior, and aligned the lifecycle documentation and tests ([PR #32](https://github.com/csc301-2026-f/20-AMD-Schola/pull/32)).
- Integrated the team's D3 work by handling merges of multiple feature and infrastructure PRs, reconciling shared APIs and build changes, and preparing the D3 submission branch. The integrated work includes native adapters, spaces, lifecycle, configuration, inference, transport infrastructure, and the current demo; feature ownership remains with the respective authors.
- Maintained and fixed CI/CD: added SCons build caching ([PR #37](https://github.com/csc301-2026-f/20-AMD-Schola/pull/37)), job timeouts, D3 host/ONNX checks, and two-instance training/export checks. Fixed the smoke job's Python version, Godot's first-import shutdown handling, the retired macOS runner, and the exported application's test entry point. Required explicit smoke completion and bounded package checks to prevent silent passes or hangs.
- Added runtime-only D3 packaging for Windows, Linux, and macOS, package checks on PRs, automatic development prereleases after successful `main` runs, and publication from the `D3` tag. Verified the [complete candidate CI run](https://github.com/csc301-2026-f/20-AMD-Schola/actions/runs/42157175290), including native/Godot tests and successful exported ONNX playback on all three platforms. Kept inference packages separate from unfinished training transport dependencies.
- Updated the D3 README, product-evolution report, demo setup and test instructions, infrastructure documentation, and current implementation status. Recorded partner and TA meeting progress ([PR #31](https://github.com/csc301-2026-f/20-AMD-Schola/pull/31), [PR #33](https://github.com/csc301-2026-f/20-AMD-Schola/pull/33)).

## Bohdan Zmeul - ONNX inference and packaging (US7)

- Completed the US7 runtime ([PR #16](https://github.com/csc301-2026-f/20-AMD-Schola/pull/16)). Implemented `ScholaInferenceStepper`, which runs observe, infer, and act for its agents every physics frame without Python, with Inspector setup, runtime agent management, memory resets, configuration warnings, and an `inference_failed` signal.
- Replaced `initialize_spaces()` with `initialize(agent)` in `ScholaOnnxPolicy`, so a policy reads its spaces from the agent and checks them against the model. Kept recurrent memory per agent in `ScholaPolicyState`, so agents can share one loaded model.
- Added one error-handling pattern for the US7 Godot classes through `interop/godot_status.h`, and aligned failure behavior with Unreal Schola where practical: if one agent's observe or act fails, the other agents still act.
- Fixed inference failures: out-of-range Box actions from trained models are now clamped to the action space, changing the policy or removing an agent during a step no longer risks a crash, out-of-range Discrete observations are rejected, a repeated failure is reported once, and changing `model_path` now loads the new model instead of silently keeping the old one.
- Added US7 tests: a Godot integration suite for the stepper (`schola_inference_test.gd`), native tests for policy, state, and stepper behavior, and comparisons with Python's ONNX Runtime on SB3 PPO and RLlib LSTM models from Schola's exporter, including LSTM memory across steps.
- Verified Windows debug and release exports running a policy without Python or the training add-on. Wrote the inference and packaging guide (`Godot/docs/us7_inference_api.rst`) and kept the US7 status current.
- Improved the D3 demo's missing-policy message and instructions ([PR #43](https://github.com/csc301-2026-f/20-AMD-Schola/pull/43)). Proposed US14 for reading the state sequence length from model metadata.
- Reviewed and approved [PR #32](https://github.com/csc301-2026-f/20-AMD-Schola/pull/32).

## Jimmy Zhu - Spaces, points, tests, and D3 demo

- Completed US2 ([PR #36](https://github.com/csc301-2026-f/20-AMD-Schola/pull/36)): observations converted from Godot are now validated against their space, so out-of-bounds values are rejected at the boundary instead of passing through unchecked. Integer and bool Box spaces now follow Python Schola's dtype rules, requiring finite, whole-number bounds and values within the dtype's `std::numeric_limits` range, checked before narrowing to float32.
- Cleaned up the US2 API: removed the unused `variant_to_space` / `space_to_variant` conversion, replaced a duplicate dtype-name table with `schola::dtype_name()`, made `ScholaSpace` build its space once per call, and switched the training host to encode definition spaces with `space_to_dictionary`. Added Catch2 and GdUnit4 tests for integer and bool Box rules and MultiDiscrete / MultiBinary value conversion ([PR #36](https://github.com/csc301-2026-f/20-AMD-Schola/pull/36)).
- Built the D3 demo in `Godot/demo/d3/` ([PR #42](https://github.com/csc301-2026-f/20-AMD-Schola/pull/42)), rebuilding the D2 grid world on the current native implementation. `GridEnvironment` and `GridAgent` extend the native `ScholaEnvironment` and `ScholaAgent`, and keyboard play, Python training, and ONNX playback all run through one `ScholaTrainingHost` session. ONNX playback uses the US7 `ScholaOnnxPolicy` / `ScholaPolicyState` API in place of D2's GDScript Q-table reader.
- Added parallel training to the demo: a launcher that starts N headless instances with their own ports and host sessions, a trainer that steps them in lockstep to learn one shared Q-table (3.0× faster with 4 instances, 5.0× with 8), and a single-window viewer showing a live board per instance ([PR #42](https://github.com/csc301-2026-f/20-AMD-Schola/pull/42)).
- Added map editing to the demo (toggle hazards, move the goal, resize from 3×3 to 10×10, save to `user://d3_map.json`). Observation bounds follow the map size, and policies record their training map so playback warns on a mismatch. Also added the compact 2D HUD, export presets, the demo README, and the headless `d3_smoke.gd` test covering seeding, goal, hazard, timeout, custom maps, and ONNX playback ([PR #42](https://github.com/csc301-2026-f/20-AMD-Schola/pull/42)).

## Isaac Tilahun - gRPC connector (US3) and Godot agent adapter (US1)

- Built `GrpcConnector` (`Godot/src/transport/grpc/grpc_connector.cpp`), the server Schola's Python trainer connects to, taking it over from Sanjay. It answers Python's three calls: start, "what can I train?", and reset or step. gRPC receives each call on its own thread, but only Godot's main thread may touch the game, so the connector hands each call over and waits for the answer. It never hangs: every wait has a timeout, a Python disconnect ends the session, and game errors reach Python with the name of the call that failed. It accepts messages up to 100 MB, so camera-sized observations fit.
- Wrote eight tests that run the connector over a real network connection on one machine, with a small C++ client playing Python (`Godot/tests/transport/grpc_connector_test.cpp`). One runs a full session with two environments of two agents each and checks that every action and reward reaches the right agent. One sends an 8 MB observation. The others break the session on purpose (Python never connects, goes silent, reports an error, or hangs up mid-call; the game fails; the port is taken) and check that it ends with a clear error instead of hanging. All 21 transport tests pass locally on Windows.
- Built the transport on Windows for the first time and fixed what broke: a Windows macro named `ERROR` clashed with Schola's generated `ERROR` status value. Defining `NOGDI` for gRPC builds in `Godot/SConstruct` keeps it out. CI only builds on Linux, so it had not caught this.
- Connected the connector to Guneev's message conversions from [PR #35](https://github.com/csc301-2026-f/20-AMD-Schola/pull/35), so it uses the same translation between Python's messages and Schola's types as the rest of US3.
- For US1, wrote the Godot agent adapter (`godot_agent_adapter.*`), which lets a GDScript agent act as a Schola agent, and drafted the environment adapter's interface. Both shipped in [PR #34](https://github.com/csc301-2026-f/20-AMD-Schola/pull/34), where Sanjay finished the environment adapter.
- Wrote the US3 slides and speaker script for the D3 demonstration, and kept the US3 progress notes current.

## Guneev Pannu - US3 training-message conversion

- Implemented the US3 conversions between GymService protobuf messages and Schola's engine-independent training types ([PR #38](https://github.com/csc301-2026-f/20-AMD-Schola/pull/38)) so Schola can work and survive indepentendly of protobuf's behaviour
- Fixed training replies that flattened multi-dimensional Box observations and lost dtype ([PR #40](https://github.com/csc301-2026-f/20-AMD-Schola/pull/40)). SO a 2 x 3 observation doesn't get collapsed into a 1 x 6 array
- Both changes merged into the US3 gRPC connector branch and shipped with the transport packaging PR ([PR #35](https://github.com/csc301-2026-f/20-AMD-Schola/pull/35)). Co-authored the vendored gRPC/protobuf dependency packaging ([PR #41](https://github.com/csc301-2026-f/20-AMD-Schola/pull/41)).
- Added `Godot/tools/test.sh` so unit, inference, transport, and integration suites can be built and run from one easy entry point.
- Extended US4 so agent membership can change during a session: possible IDs and spaces stay fixed in the training definition, while live agents may spawn or leave at reset/step boundaries. Not merged yet (`Guneev/dynamic-training-populations`). Lets rl environments where agents can spawn other agents.

## Vansh Sehrawat - Godot configuration, editor tools, and partner liaison (US5)

- Extended the native US5 bindings with Godot-native agent and environment configuration ([PR #39](https://github.com/csc301-2026-f/20-AMD-Schola/pull/39)). Empty agent IDs now resolve to the node name, and empty agent types resolve to the effective agent ID, without changing saved Inspector values. Integrated these defaults into the US1 adapters and added Inspector help for identities, observation/action spaces, defaults, and resource sharing.
- Implemented live configuration warnings for missing or invalid spaces, missing agents, duplicate resolved IDs, and missing required behavior hooks. Duplicate-ID warnings identify both conflicting node paths. Warnings refresh after nested-resource edits, script changes, agent addition/removal, renaming, and reparenting; inherited hooks are recognized without running gameplay scripts in the editor ([PR #39](https://github.com/csc301-2026-f/20-AMD-Schola/pull/39)).
- Consolidated reward, termination, truncation, and info callbacks into `_get_step_result(agent)`, while keeping `_reset_episode(seed, options)` separate. Added strict validation for finite float32 rewards, boolean completion flags, and string-to-string info, with agent-specific errors and no partial result batches. Updated the native adapter and integration-test environments to use the revised contract ([PR #39](https://github.com/csc301-2026-f/20-AMD-Schola/pull/39)).
- Applied AMD's feedback on episode limits by removing built-in step-limit handling from the node API and lifecycle, and dropping the proposed special-purpose `MaxEpisodeSteps` node. Environment authors now implement cutoffs through `truncated: true`; documented the distinction between natural termination and external truncation ([PR #39](https://github.com/csc301-2026-f/20-AMD-Schola/pull/39)).
- Built the GDScript Schola editor dock with native-capability reporting, scene-node selection, and undoable monitor insertion. Added `ScholaMonitor` for externally supplied episode/step counts, per-agent rewards and returns, completion status, and bounded reward history, plus an interactive preview using sample telemetry. Fixed the dock layout so it stays within the editor window ([PR #39](https://github.com/csc301-2026-f/20-AMD-Schola/pull/39)).
- Added regression coverage for identity defaults and scene persistence, configuration diagnostics, callback ordering and validation, user-defined truncation, and monitor behavior. Added the optional native adapter test driver, enabled it in CI, and fixed a test-driver crash. Completed manual editor persistence checks and recorded the Windows build, integration-test, warning-refresh, and layout verification in the US5 progress documentation ([PR #39](https://github.com/csc301-2026-f/20-AMD-Schola/pull/39)).

## Sanjay Ram - Developer & Meeting Manager (US1, US3, QA, Meeting Notes)

- Implemented the environment adaptor, connecting Schola's environment API to a ScholaEnvironment scene. This builds on US1's agent adapter. ([PR #34](https://github.com/csc301-2026-f/20-AMD-Schola/pull/34))
- Worked on ([PR #35](https://github.com/csc301-2026-f/20-AMD-Schola/pull/35)), with the following changes done:
    - Removed non blocking polling methods from the connector loop based on partner feedback, and only kept the blocking method
    - Set up the gRPC and Protobuf build for Godot
    - Wrote a python scrip thta tbuilds versions in the dependency json for Windows and Linux.
    - Also integrated gRPC configs to our SCons build.
    - Also added macOS configurations as well.
    - Adjusted the CI so it builds the gRPC, and with coordination with Shahyar, integrated a cache to save time with the CI time.
- QA work, reviewing and approving 3 PRs:
    - [PR #33](https://github.com/csc301-2026-f/20-AMD-Schola/pull/33)
    - [PR #38](https://github.com/csc301-2026-f/20-AMD-Schola/pull/38)
    - [PR #40](https://github.com/csc301-2026-f/20-AMD-Schola/pull/40).
- Recorded the minutes for partner meeting 7 and TA meeting 4.
