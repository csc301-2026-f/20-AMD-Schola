# AMD codebase map and maintenance guide

This guide explains where the Godot port lives and how to continue developing or integrate it. The course repository and its tagged snapshots provide the source reference. Future upstream destination, ownership, and integration arrangements are to be discussed with Alex; no repository transfer or ongoing support commitment is implied.

## Where everything is

| Location | Responsibility |
| --- | --- |
| `Godot/src/core/` | Engine-independent environments, agents, spaces, lifecycle, connector loop, policy state, and stepper contracts |
| `Godot/src/bindings/` | Godot nodes/resources, scene adapters, spaces, lifecycle, components, and inference bindings |
| `Godot/src/inference/` | ONNX Runtime loading, input/output conversion, policy execution, and recurrent state |
| `Godot/src/transport/grpc/` | gRPC server and shared protocol conversions |
| `Godot/src/training/` | Training extension entry point, connector node, and backend connecting transport to the runtime host |
| `Godot/src/interop/` | Conversion of spaces and points at extension boundaries |
| `Godot/addons/schola/` | Runtime descriptor, editor dock/Inspector/monitor, reusable GDScript components, and generated platform binaries |
| `Godot/addons/schola_training/` | Separate training extension descriptor and generated binaries |
| `Godot/examples/` | Current component, manual environment, multi-agent, and space-definition examples |
| `Godot/tests/` | Catch2 unit/inference/transport tests and GdUnit4 integration suites |
| `Godot/SConstruct`, `dependencies.lock.json`, `requirements*.txt` | Build targets, dependency/toolchain pins, and formatting tools |
| `Godot/tools/`, `Godot/vendor/` | Dependency setup/verification, packaging, committed native packages, licenses, and provenance |
| `Proto/`, `Resources/python/` | Shared Schola wire protocol and Python trainers/export tooling |
| `Source/`, `Docs/Sphinx/` | Existing Unreal implementation and upstream documentation; not the Godot implementation |
| `.github/workflows/` | Required validation, plugin packaging, D4 publication, and explicit dependency rebuilds |
| `Godot/docs/user_stories/`, `deliverables/team/minutes/` | Scope, story ownership/evidence, remaining work, and partner decisions |
| `deliverables/D1` through `D3`, `Godot/demo/` | Historical course submissions and demos; preserve submitted artifacts |

## Set up and validate a checkout

Follow [the developer README](../README.md#build-and-run), including Git LFS, pinned submodules, Python 3.12, the supported C++ compiler, Godot 4.7.2, and native dependency installers. Build the runtime and training extensions on Windows or Linux. For inference-only use, the `schola` target needs ONNX Runtime but no gRPC installation.

Run Catch2 unit, inference, and transport suites plus GdUnit4 integration tests using [the documented commands](../README.md#supported-toolchain). Build with `integration_tests=yes` to include the native test helpers used by the training integration suites, as CI does. These tests exercise protocol/lifecycle behavior; also follow the production example's story record for real training, learning evidence, export, and playback validation.

For distributions, use [the package guide](distribution.md). Record the source commit and platform when reporting failures. A release ZIP is a runtime installation; a source checkout is the development/training environment.

## Make a change

1. Locate the responsible module and story before editing. Read [CONTRIBUTING.md](../../CONTRIBUTING.md) and [the development contract](development_contract.md).
2. Keep reusable logic under `src/core`; Godot, gRPC, and ONNX headers remain in their adapters. Only the Godot main thread touches the scene tree. Return explicit failures and translate diagnostics at the binding boundary.
3. Extend sensors/actuators through the existing component API where possible. Register new native bindings through the module's `register_types` hook. Keep editor resources and warnings consistent with runtime validation.
4. Add behavior-focused coverage in the existing test suite for the affected boundary. Re-run native and Godot integration checks when public contracts, lifetime, or serialization change.
5. Update the relevant user/developer documentation. Open a focused PR, obtain teammate review, and require passing CI before merging.

The runtime/training split is intentional: exported games should not require Python, gRPC, or training-only nodes. Core status and protocol semantics are shared with Schola; avoid introducing a Godot-only wire format or competing lifecycle rules.

## Protocol and dependency changes

`Proto/` is authoritative. SCons generates Godot bindings under ignored `Godot/generated/proto/`; do not hand-edit generated code. Python/Unreal generation and compatibility requirements are explained in CONTRIBUTING. Validate both ends when changing shared messages.

Update dependency versions centrally in the lock, acquisition scripts, manifests, and CI together. Preserve package provenance, checksums, and license notices. Normal builds install committed ONNX Runtime and gRPC packages; source rebuilding gRPC is an explicit maintenance operation, not a routine PR step. New platform support requires matching native dependencies, extension descriptors, package checks, and documented toolchain support.

## Known boundaries and evidence

- Runtime archives target Windows/Linux x86_64 and macOS arm64. Committed training dependencies and the documented Python CLI workflow target Windows/Linux.
- Real camera capture depends on a compatible renderer/viewport; a deterministic fake camera test does not prove every rendered export works.
- Training defaults to trusted localhost use. Remote authentication/TLS deployment is not supplied by these instructions.
- Story records distinguish merged code, synthetic fixtures, real-trainer checks, and remaining upstream limitations. Consult [the story index](user_stories/README.md) and [remaining work](user_stories/remaining.md) before expanding scope.
- Submitted demos and deliverable reports describe their own snapshots. Use current examples and developer docs for new work.

For the partner walkthrough, start at the root README, use this map to locate each module, and show the clean source setup, tests, shared protocol boundary, and distribution channels. Record decisions from the Friday meeting in a new meeting record rather than guessing future AMD ownership arrangements.
