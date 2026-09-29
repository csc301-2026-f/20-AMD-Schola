# AMD Schola for Godot

This folder contains Team 20's Godot prototype for AMD Schola.

The prototype demonstrates the proposed Godot workflow for creating a local reinforcement-learning environment using Godot nodes and the Inspector. It is being developed for CSC301 Deliverable 1.

## Run the prototype

1. Open the `Godot` folder as a project in Godot 4.
2. Enable **AMD Schola** in **Project > Project Settings > Plugins**.
3. Open the demo scene in `demo/`.
4. Press **Play** and use the on-screen instructions to move the agent.

The demo displays rewards for forward movement, backward movement, and remaining still.

## Scope

This is an interactive frontend prototype only. It does not include Python training, gRPC communication, model inference, persistence, or a connection to the existing Unreal implementation.

## Folder overview

- `addons/amd_schola/` — the Godot add-on.
- `demo/` — the interactive demonstration scene.
- `assets/` — prototype assets.
