# AMD Schola for Godot

This folder contains the Godot prototype for AMD Schola.

The prototype demonstrates the proposed Godot workflow for creating a local reinforcement-learning environment using Godot nodes and the Inspector.

## Run the prototype

1. Open the `Godot` folder as a project in Godot 4.
2. Enable **AMD Schola** in **Project > Project Settings > Plugins**.
3. Open the demo scene in `demo/`.
4. Press **Play** and use the on-screen instructions to move the agent.

The demo displays rewards for forward movement, backward movement, and remaining still.

## Scope

This is an interactive frontend prototype only. It does not include Python training, gRPC communication, etc.

## Folder overview

- `addons/amd_schola/` - the Godot plugin/add-on.
- `demo/` - the interactive demonstration scene.
- `assets/` - prototype assets.
