# Schola for Godot

This directory contains the Godot port of AMD Schola. The design keeps reusable reinforcement-learning logic independent from Godot, gRPC, and ONNX so that each part can be developed and tested separately.

## Supported toolchain

| Component | Initial baseline |
| --- | --- |
| Godot | 4.7.2 |
| `godot-cpp` | `10.0.0-stable` (`507ed9d840c01a3c5b2a39af8bb4000bfac30bf5`) |
| C++ | C++17, matching `godot-cpp` |
| SCons | 4.10.1 |
| Primary CI | Ubuntu 22.04, x86-64, GCC |
| Local development | Linux/GCC and Windows/MSVC |

Dependency sources, versions, supported archives, and checksums are centralized in [`dependencies.lock.json`](dependencies.lock.json). `godot-cpp` is a pinned Git submodule. The training target will reuse the repository's bundled gRPC and Protocol Buffers builds. ONNX Runtime will be obtained from the pinned CPU release archives when inference is connected. Feature branches must not select dependency versions independently. Neither gRPC nor Protocol Buffers is linked into the runtime target.

## Build and run

From a fresh checkout:

```sh
git submodule update --init --recursive
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r Godot/requirements.txt
scons -C Godot platform=linux target=template_debug -j"$(nproc)"
godot --editor --path Godot
```

On macOS, use `platform=macos` and replace `$(nproc)` with `$(sysctl -n hw.logicalcpu)`. On Windows, use the same SCons command with `platform=windows` from a developer shell. Build products are copied into the matching `Godot/addons/*/bin/<platform>/` directory and are not committed.

The `schola` target contains the runtime extension. The `schola_training` target is a separate training extension and may depend on runtime/core code as transport support is added. The example project loads `examples/basic_environment/main.tscn`, which instantiates `ScholaRuntimeProbe`. The runtime and training probe nodes exist only to verify extension registration and loading; they are not production APIs for any user story.

The extension entry points are stable composition roots. Runtime bindings and inference register through their own `register_types` files, and training-only bindings register through `src/training/bindings/register_types`. Feature branches add registrations only to the hook owned by their module; they do not add production classes directly to the runtime or training composition roots.

## Directory structure

```text
Godot/
├── src/
│   ├── core/
│   │   ├── environment/          Environment and agent contracts
│   │   ├── spaces/               Observation/action spaces and point values
│   │   └── lifecycle/            Step, reset, and auto-reset coordination
│   ├── bindings/                 Godot nodes and Inspector bindings
│   ├── inference/                ONNX policy implementation
│   └── transport/grpc/           gRPC and Protocol Buffer integration
├── addons/
│   ├── schola/                   Runtime add-on packaging
│   └── schola_training/          Training-only add-on packaging
├── examples/
│   └── basic_environment/       End-to-end demonstration environment
└── tests/
    ├── unit/                    Fast tests for individual modules
    └── integration/             Cross-module and Python compatibility tests
```

## Module boundaries

### `src/core`

Contains the engine-independent environment interfaces, space and point types, agent state, connector loop, and transport/policy abstractions. It must not reference Godot, gRPC, or ONNX libraries.

### `src/bindings`

Adapts the core abstractions to user-facing Godot nodes, resources, the Inspector, and the engine lifecycle. User-facing Godot APIs belong here. The `src/runtime` and `src/training` composition roots may use the minimal Godot registration APIs needed to assemble and initialize their extensions; they must not define user-story APIs.

### `src/transport/grpc`

Implements the core transport abstraction using Schola's existing Protocol Buffer and gRPC contracts. Keeping it separate prevents networking dependencies from leaking into the core or inference-only builds.

### `src/inference`

Implements the core policy abstraction using ONNX Runtime. It supports local inference without a running Python process or training connection.

### Godot add-ons

- `addons/schola/` contains runtime functionality required by both development projects and exported games.
- `addons/schola_training/` contains training and communication integration. Exported games must be able to exclude this add-on while retaining runtime inference.

## Dependency direction

```text
bindings ──→ core ←── inference
               ↑
        training transport
```

Dependencies must point toward `core`. The core must never depend on Godot bindings, gRPC, Protocol Buffers, or ONNX Runtime. The training add-on may depend on the runtime add-on, but the runtime add-on must not depend on training code.

## User-story mapping

| User story | Primary location |
| --- | --- |
| US1: Define an environment | `src/core/environment/` |
| US2: Declare spaces | `src/core/spaces/` |
| US3: Connect Python training tools | `src/transport/grpc/` and `addons/schola_training/` |
| US4: Execute the episode lifecycle | `src/core/lifecycle/` |
| US5: Configure through Godot | `src/bindings/` and `examples/basic_environment/` |
| US6: Export a policy to ONNX | Existing Python Schola package under `Resources/python/` |
| US7: Run and ship an ONNX policy | `src/inference/` and `addons/schola/` |

The detailed acceptance criteria and D1 planning scope are in [`deliverables/D1/planning.md`](../deliverables/D1/planning.md). Engineering tasks, dependencies, assignees, and progress are tracked on the team's [Trello board](https://trello.com/b/Ry0Qkx2R).

## Code style and formatting

Godot C++ code follows the conventions enforced by [`Godot/.clang-format`](.clang-format), based on the official `godot-cpp` configuration. Use clang-format 17 so every contributor and CI produce the same output. The [`Godot/.editorconfig`](.editorconfig) file configures compatible whitespace and line-ending defaults for supported editors.

From the repository root, format all tracked Godot C++ files with:

```sh
git ls-files ':(glob)Godot/**/*.cpp' ':(glob)Godot/**/*.h' | xargs clang-format -i
```

Check formatting without modifying files with:

```sh
git ls-files ':(glob)Godot/**/*.cpp' ':(glob)Godot/**/*.h' | xargs clang-format --dry-run --Werror
```

Run the check before opening a pull request. Format only team-owned source files; do not reformat generated code or vendored dependencies.

## Working on a story

1. Branch from an up-to-date `main` using the branch name recorded on the Trello card.
2. Keep changes inside the module responsible for the story. Introduce cross-module dependencies only when they follow the dependency direction above.
3. Add unit tests for engine-independent behavior and integration tests for interactions between Godot, transport, Python, and inference.
4. Open a pull request and link its Trello card. Do not merge until the relevant tests pass and another team member has reviewed it.

Generated Godot state, build output, local models, and editor-specific files must not be committed.
