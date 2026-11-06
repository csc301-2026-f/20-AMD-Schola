# Schola for Godot: Product Evolution

## 1. What Needed to Improve

D2 demonstrated a useful reinforcement-learning workflow, but it did not yet show that the production Godot modules could run that workflow together. Its grid-world used native observation/action spaces, configuration nodes, and ONNX inference, while GDScript stand-ins implemented environment behavior, episode coordination, and training communication. The most important gap was therefore integration: a successful D2 run could hide defects in production environment and lifecycle code because those components were not on the demo's execution path. The [D2 iteration review](../D2/iteration-02-review.md) identified replacing stand-ins as the next priority. AMD's request for a small trained example, recorded in the same review, supported improving one understandable workflow rather than adding unrelated features.

D3 moves that example onto the native environment and lifecycle interfaces, updates inference to the current policy-state API, and makes the task editable and observable during parallel training. The remaining JSON/TCP training connector is identified explicitly. We do not present the demo as completed integration with Schola's existing production Python clients.

## 2. What You Did

### Integrate the production environment and lifecycle

The [native environment adapters, PR #34](https://github.com/csc301-2026-f/20-AMD-Schola/pull/34), connect GDScript behavior to the engine-independent environment and agent interfaces. The [training host, PR #32](https://github.com/csc301-2026-f/20-AMD-Schola/pull/32), exposes session initialization, definition, reset, step, and close to Godot and discovers environments within the active scene. [Configuration changes in PR #39](https://github.com/csc301-2026-f/20-AMD-Schola/pull/39) align identities, Inspector diagnostics, and the consolidated `_get_step_result` callback. [PR #36](https://github.com/csc301-2026-f/20-AMD-Schola/pull/36) completes the space-resource and conversion work used at these boundaries.

The [D3 demo, PR #42](https://github.com/csc301-2026-f/20-AMD-Schola/pull/42), uses those native components directly. `GridEnvironment` and `GridAgent` implement task-specific observation, action, reset, reward, and completion hooks. The runner submits manual, Python, and policy actions through one `ScholaTrainingHost` session. This makes the native host responsible for the same episode transitions in all three modes. The environment implements its 40-step cutoff by reporting truncation, rather than relying on a special step-limit node or a second lifecycle implementation.

Integration required respecting session lifetime. An environment initializes once, and its declared spaces remain fixed for the session. The demo therefore uses disabled autoreset, reloads after map changes, and validates incoming actions before a host step. If a host failure closes the session, the UI reports that state and offers reload instead of attempting to reuse an invalid session. These constraints are documented in the [D3 guide](../../Godot/demo/d3/README.md#host-session-rules).

### Update inference and make the task inspectable

[PR #16](https://github.com/csc301-2026-f/20-AMD-Schola/pull/16) implements the current policy, recurrent-state, Godot binding, and packaging design. D3 initializes `ScholaOnnxPolicy` against the agent, creates a per-agent `ScholaPolicyState`, and resets that state between episodes. The demo's previous GDScript Q-table playback path is removed; playback uses ONNX Runtime with Python closed. Python still saves a Q-table as training output, then converts it to ONNX and compares the exported model's actions with the table.

The map editor lets a tester change the grid dimensions, move the goal, and add hazards. Saving reloads the scene so the host definition matches the new observation bounds. Map validation rejects invalid sizes and coordinates; the panel reports unreachable free cells. A policy is tied to its training layout because hazards are absent from the observation. The trainer records the map alongside its model, and playback warns about a mismatch. This limitation is visible rather than hidden behind a claim that the policy generalizes.

Parallel training starts separate headless Godot processes and learns one shared Q-table from their experience. The viewer displays each board, connection freshness, training progress, rewards, and aggregate throughput. This is synchronous multi-process training: each round waits for all instances. It is not multiple environments inside one Godot process or distributed training across machines. The [demo guide](../../Godot/demo/d3/README.md#parallel-training) documents the launcher, ports, and logs.

### Make checks and distribution repeatable

The repository already had formatting, native tests, and Godot integration checks. D3 adds checks of the actual demo: generate a reference model, verify native-host behavior and successful reference-policy playback, run two trainer-driven instances for 20 total episodes, export their Q-table, and load that export in Godot after the trainer exits. The short training run checks the integration path; it does not establish convergence or a success-rate benchmark.

The smoke script also checks that its main, custom-map, and policy checks finish. This matters because a GDScript runtime error can interrupt a check without making the process return a failing exit code. Required-policy mode prevents a missing ONNX artifact from silently skipping inference, and reference-policy mode requires the agent to reach the goal.

[D3 packaging](../../.github/workflows/d3-release.yml) builds runtime-only libraries and desktop archives for Windows x86_64, Linux x86_64, and macOS arm64. Source and exported-package smoke checks run before package upload. Relevant PRs include packaging in the aggregate required check; successful `main` runs publish commit-specific development prereleases. The `D3` tag publishes the course snapshot. The packaged policy is a deterministic shortest-path reference for immediate evaluation, not a claim of successful learning. Actual platform results must be checked in [GitHub Actions](https://github.com/csc301-2026-f/20-AMD-Schola/actions); a workflow definition alone is not evidence that its final revision passed.

## 3. Before vs. After

| Concern | D2 | D3 | Evidence |
| --- | --- | --- | --- |
| Environment behavior | Scripted demo adapter | Native agent/environment adapters with task hooks | PRs #34, #39; [demo environment](../../Godot/demo/d3/demo/grid_environment.gd) |
| Episode execution | Demo-owned stepping/reset behavior | One native host session for manual, training, and policy modes | PR #32; [runner](../../Godot/demo/d3/addons/schola_d3/runtime/demo_runner.gd) |
| Policy playback | Earlier inference API and scripted table path | Agent initialization and per-agent ONNX policy state | PRs #16, #42; [policy smoke check](../../Godot/demo/d3/tests/d3_smoke.gd) |
| Task configuration | Authored fixed demo map | Validated editable maps with reload and policy-mismatch warnings | [Map workflow](../../Godot/demo/d3/README.md#changing-the-map) |
| Parallel training | No equivalent viewer in the submitted D2 workflow | Multiple headless processes and live mini boards | [Parallel workflow](../../Godot/demo/d3/README.md#parallel-training) |
| Distribution checks | D2-only release workflow | D3 package checks on PRs, automatic development releases, tagged submission packages | [Godot CI](../../.github/workflows/godot.yml), [packaging](../../.github/workflows/d3-release.yml) |

The behavioral checks are concrete: the default map has a 40-step cutoff; reaching the goal yields 9.9 on the final step, hitting a hazard yields -10.1, and repeated seeded resets reproduce the start. The smoke script also checks a custom 4x4 map and its observation bounds. The default reference policy contains 32 non-hazard states, and export checks agreement for every table entry. These are reproducible examples, not an inferred performance improvement.

Local Windows validation on November 5 rebuilt the runtime, passed the reference-policy smoke check with a successful episode, then completed the two-instance 20-episode run and exported a 36-state learned table. Loading that export in Godot after the trainer exited passed the host/inference checks; its evaluation episode timed out, reinforcing why the short integration check is not a learning-quality claim. Negative checks returned exit code 1 for a missing required model and interrupted check groups. The 13 dependency-installer tests and two build-target tests also passed locally. Cross-platform package execution and the final hosted CI result remain to be established by Actions.

The [README's NFR section](../../README.md#non-functional-requirements) explains input validation, connection timeouts, visible errors, loopback-only default communication, keyboard movement, and separation of training dependencies from exported inference. Accessibility remains partial: map editing requires pointer interaction, and screen-reader support has not been verified. No remote authentication or production security claim is made for the temporary local connector.

## 4. Reflection

Keeping one small grid-world made integration behavior easier to explain and inspect. Manual movement, training, and inference now exercise the same native session, so the example provides evidence about the product modules rather than only a parallel demo implementation. Separating the runtime build from the training extension also makes packaging possible without requiring unfinished gRPC integration.

The difficult work was aligning contracts across branches: space serialization, identity resolution, environment callbacks, session lifetime, and policy state all affect the same end-to-end path. Integrating these changes required more than merging files. A stale runtime library can disagree with current scripts, and a smoke test can return success after a script error unless completion is checked. This is why the workflow rebuilds the runtime and validates both the source example and exported package.

D4 should prioritize the concrete gRPC connector, its Godot integration, and compatibility with existing Schola Python training tools. [PR #35](https://github.com/csc301-2026-f/20-AMD-Schola/pull/35) supplies dependency packaging and training-message conversions, but the current tree still lacks `grpc_connector.cpp`; those changes do not complete production transport. Clean-checkout installation, reliable training/export/inference, and packaging remain the release priorities. Proposed sensors, actuators, camera observations, and other follow-up stories should not displace that work. D3 leaves a narrower integration gap and a repeatable way to test the example while that gap is closed.
