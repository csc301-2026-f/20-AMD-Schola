# Godot demos

These standalone projects demonstrate milestone-specific workflows without mixing prototype code into the production GDExtension under `Godot/src`.

- [`d1`](d1) is the original C# interface prototype.
- [`d2`](d2) is the GDScript training and ONNX inference demo. Its README identifies which components use production C++ and which remain demonstration stand-ins.
- [`d3`](d3) rebuilds the D2 grid world on the native US1 environment and agent nodes, the US4 `ScholaTrainingHost`, and the current US7 ONNX policy API. Only the US3 transport and the Python trainer remain stand-ins.
