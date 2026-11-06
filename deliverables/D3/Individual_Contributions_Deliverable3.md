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

**[Name]**, [Role]
> [Specific contributions]

**[Name]**, [Role]
> [Specific contributions]

**[Name]**, [Role]
> [Specific contributions]
