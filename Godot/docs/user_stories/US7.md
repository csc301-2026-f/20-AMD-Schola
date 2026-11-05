# US7: Run and ship an ONNX policy

- **Owner:** Bohdan
- **Status:** In progress
- **Last updated:** Nov. 4, 2026

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

- The core policy API, ONNX loading, per-agent recurrent state, and observe-infer-act loop are implemented and tested, including the automatic physics loop.
- Real RLlib LSTM and Stable-Baselines3 PPO exports match Python's ONNX Runtime results.
- Training-only dependencies are separated from the inference add-on.
- Windows debug and release exports run the policy without Python or the training add-on.
- Remaining work includes a demonstration agent with learned behavior, exports on Linux and macOS, attention models from a real trainer, and reading the sequence length from model metadata.
