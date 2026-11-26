# Installing and distributing the Godot plugin

Schola is a native plugin installed into a Godot project. Our dev and release/prod environments are distribution channels, with separate destinations and revision selection; they are not hosted application servers.

## Channels and package contents

| Channel | Trigger | Destination | Revision |
| --- | --- | --- | --- |
| Dev | Push to `main`; required PR checks also build candidate packages | Successful [Godot Actions run](https://github.com/csc301-2026-f/20-AMD-Schola/actions/workflows/godot.yml), under Artifacts | The run's source commit, recorded in `BUILD.txt` |
| Release/prod | Scheduled D4 publisher or manual dispatch from `main` | [D4 GitHub release](https://github.com/csc301-2026-f/20-AMD-Schola/releases/tag/D4) | The publisher's source commit, pinned by the D4 tag |

The same reusable `godot-packages.yml` builds the runtime in debug and release configurations, creates the plugin archive, extracts it into a clean project, imports it with the pinned Godot editor, and verifies the native runtime classes load. Upload occurs after this check succeeds. The D4 publisher waits for every packaging platform and refuses to move an existing D4 tag to another commit.

Archives are named:

- `Schola-Godot-windows-x86_64.zip`
- `Schola-Godot-linux-x86_64.zip`
- `Schola-Godot-macos-arm64.zip`

Each contains:

```text
addons/schola/
  plugin.cfg                 Editor plugin entry
  schola.gdextension         Runtime extension descriptor
  schola_plugin.gd           Editor dock
  space_inspector.gd         Resource Inspector
  components/                Reusable sensors, actuators, and shaders
  ui/                        Episode monitor
  bin/<platform>/            Debug/release runtime and ONNX Runtime library
licenses/onnxruntime/         ONNX Runtime license and third-party notices
licenses/godot-cpp/           godot-cpp license
LICENSE.txt                  Schola license
INSTALL.md                   This guide
BUILD.txt                    Source commit, platform, architecture, package scope
```

These are runtime/editor packages. `ScholaTrainingHost` is part of the runtime, but `ScholaTrainingConnector` requires the separate training extension and is not included. Build training from source on Windows or Linux using the developer guide. macOS runtime packages do not imply support for Schola's Python CLI on macOS.

## Install into your project

1. Use Godot 4.7.2 and download the archive matching your operating system and CPU. When downloading from Actions, extract the artifact wrapper first to obtain the plugin ZIP.
2. Close Godot. Extract the plugin ZIP outside your project, then copy `addons/schola/` into your project's `addons/`. Keep `LICENSE.txt`, `licenses/`, and `BUILD.txt` with your distribution records.
3. Open the project. Godot imports `schola.gdextension` and loads the platform's debug runtime. Enable **AMD Schola** under **Project Settings > Plugins** to show the Schola dock and Inspector tools.
4. Confirm native types such as `ScholaEnvironment`, `ScholaAgent`, and `ScholaOnnxPolicy` are available. Follow the repository README's workflows to create an environment or run an ONNX policy.

To update, close Godot and replace the installed `addons/schola/` with the new archive's directory; avoid mixing binaries from different builds. Retain the previous ZIP and `BUILD.txt` to roll back by restoring that directory. Preserve your environment scenes and models outside the add-on directory.

## Export a game

Include the runtime descriptor, matching release library, ONNX Runtime dependency, component scripts used by your scenes, and policy model. The descriptor declares the native dependency for Godot's exporter. Include `.onnx` files in the export preset's non-resource include filter if Godot does not select them automatically. Exclude `addons/schola_training/` and training-only scenes from an inference-only game.

The package check establishes clean-project runtime loading. It does not certify every user's exported game, renderer, camera configuration, or trained policy; verify your own export on its target platform.

## Build and test a package locally

From a source checkout, install ONNX Runtime and build both runtime configurations with the [supported toolchain](../README.md#supported-toolchain):

```sh
python Godot/tools/setup_onnxruntime.py
scons -C Godot schola platform=linux target=template_debug
scons -C Godot schola platform=linux target=template_release
python Godot/tools/package_plugin.py --platform linux --arch x86_64 --output Godot/build/Schola-Godot-linux-x86_64.zip
```

Use `platform=windows` for Windows and `platform=macos arch=arm64` for macOS in both SCons commands; match the packager arguments. Packaging fails on missing/empty required binaries, editor entry files, or runtime license notices. Inspect the resulting archive and install it into a separate clean project before distributing it. CI automates that installation check for each supported package platform.

## Troubleshooting

- **Missing native classes:** check Godot version, platform/architecture, the extension descriptor, and that the complete `bin/<platform>/` directory was copied. Read the editor's first native-library error before investigating scene scripts.
- **Missing ONNX Runtime:** restore the complete plugin package; copying only the Schola native library is insufficient.
- **Missing training connector:** expected for the runtime package. Use a source build with the committed gRPC package and both extensions.
- **Model does not load:** check that the file exists and matches the agent's effective observation/action spaces, including stacking and recurrent state. Read the model-loading diagnostic.
- **Python cannot connect:** start the training scene first, use the same localhost port in Python and Godot, and connect within `start_timeout_sec`. See [training configuration](../README.md#train-with-python).
- **Headless import crashes after completing:** the known Godot first-import shutdown issue can require a retry. CI retries the known crash codes up to three times and fails persistent errors.
- **Download unavailable:** inspect the relevant Actions run. A workflow definition or release URL alone does not establish that packages were successfully published.
