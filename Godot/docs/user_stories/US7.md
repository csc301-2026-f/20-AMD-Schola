# US7: Run and ship an ONNX policy

- **Owner:** Bohdan
- **Status:** Inference and packaging merged; production training proof tracked in US13
- **Last updated:** Nov. 18, 2026

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
- D3 supports local policy playback with Python closed. Its packaged default policy is a deterministic shortest-path reference, not proof of learned behavior. A production train/export/deploy proof remains tracked under US13; recent RaceTrack tests use an untrained Schola-exported stand-in.
