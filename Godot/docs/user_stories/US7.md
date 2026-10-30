# US7: Run and ship an ONNX policy

- **Owner:** Bohdan
- **Status:** In progress
- **Last updated:** Oct. 30, 2026

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

- The core policy API, ONNX loading, per-agent recurrent state, and observe-infer-act loop are implemented and tested.
- Training-only dependencies are separated from the inference add-on.
- Remaining work includes completing and validating the packaged export workflow and confirming recurrent-model sequence-length behavior.
- No new progress was discussed at the Oct. 30 partner meeting.
