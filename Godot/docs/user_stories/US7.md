# US7: Run and ship an ONNX policy

- **Owner:** Bohdan
- **Status:** Complete on main
- **Last updated:** Nov. 25, 2026

## Story

As a Godot developer, I want a trained policy to drive my agent with Python closed and to exclude training-only dependencies from exported games so that I can ship an autonomous agent without unnecessary training infrastructure.

## Acceptance criteria

- Godot loads the exported ONNX model and validates that its inputs and outputs match the agent's declared spaces.
- On each physics step, the agent follows an observe-infer-act loop that applies model output as its action.
- The demonstration agent performs the intended learned behavior while Python is not running.
- Missing, invalid, or incompatible model files produce a clear error.
- Training and transport code is packaged separately from the core environment API and inference code.
- A Godot export containing the demonstration environment runs its trained policy without Python or a live gRPC connection.
- The exported build excludes the training add-on without preventing the project from loading or using inference.
- The documentation identifies which modules are required for training and which are required in a shipped game.

## Progress

- The ONNX runtime, local inference stepper and runtime packaging merged in [PR #16](https://github.com/csc301-2026-f/20-AMD-Schola/pull/16) ([`d945521`](https://github.com/csc301-2026-f/20-AMD-Schola/commit/d945521)). Automatic sequence-length resolution is tracked in [US14](US14.md).
- The core policy API, ONNX loading, per-agent recurrent state, and observe-infer-act loop are implemented and tested, including the automatic physics loop.
- Real RLlib LSTM and Stable-Baselines3 PPO exports match Python's ONNX Runtime results.
- Training-only dependencies are separated from the inference add-on.
- Windows debug and release exports run the policy without Python or the training add-on.
- The demonstration agent runs its trained policy in the D3 demo with Python closed. On main, the [US13 RaceTrack](US13.md) and [US11 camera target](US11.md) examples also run exported policies through `ScholaInferenceStepper`.
- Fixes since: agent changes during stepping are guarded ([PR #63](https://github.com/csc301-2026-f/20-AMD-Schola/pull/63)); integer actions and observations that overflow the model's type are rejected ([PR #70](https://github.com/csc301-2026-f/20-AMD-Schola/pull/70), [PR #84](https://github.com/csc301-2026-f/20-AMD-Schola/pull/84)); duplicate agents are rejected ([PR #75](https://github.com/csc301-2026-f/20-AMD-Schola/pull/75)); a new stepper agent is checked against the policy's spaces ([PR #80](https://github.com/csc301-2026-f/20-AMD-Schola/pull/80)); reset clears the previous episode's observations ([PR #83](https://github.com/csc301-2026-f/20-AMD-Schola/pull/83)); an empty `ScholaPolicyState` is reported as not coming from `create_state()` ([PR #89](https://github.com/csc301-2026-f/20-AMD-Schola/pull/89)); the stepper reports a repeated error after `set_policy()` ([PR #90](https://github.com/csc301-2026-f/20-AMD-Schola/pull/90)); and its `model_path` warning clears when a model is picked ([PR #92](https://github.com/csc301-2026-f/20-AMD-Schola/pull/92)).
- Performance: the stepper swaps each new observation into its cache instead of copying it ([PR #94](https://github.com/csc301-2026-f/20-AMD-Schola/pull/94)), and float32 Box observations are copied into ONNX tensors in one step ([PR #95](https://github.com/csc301-2026-f/20-AMD-Schola/pull/95)). Their benchmarks show the largest gains for camera-sized observations.
- The D4 release ([PR #96](https://github.com/csc301-2026-f/20-AMD-Schola/pull/96)) packages the runtime and editor plugin with ONNX Runtime for Windows and Linux x86_64 and macOS arm64; see [distribution](../distribution.md).
- Open PR #99 would record the Godot-facing error-handling rules in the development contract.
