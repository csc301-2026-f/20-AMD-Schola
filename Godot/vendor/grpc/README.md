# Prebuilt gRPC and Protocol Buffers

This directory holds Godot-specific dependency packages tracked in Git LFS. Normal
CI verifies and unpacks them; it never builds gRPC from source. These packages
are independent of Unreal's binaries in `Source/ThirdParty/gRPC`.
CI fetches only its platform's ZIP through checkout's LFS support; the other
platform and Unreal's bundled archives remain unfetched. Local clones need Git
LFS installed; an existing checkout can fetch just these packages with
`git lfs pull --include="Godot/vendor/grpc/*.zip" --exclude=""`.

## Packages

| Package | Build environment | Runtime |
| --- | --- | --- |
| `linux-x86_64.zip` | GitHub-hosted Ubuntu 22.04, GCC, C++17 | Linux x86_64, glibc 2.35 or newer |
| `windows-x86_64.zip` | GitHub-hosted Windows 2022, Visual Studio 2022, C++17 | Windows x86_64, static MSVC runtime (`/MT`) |

Each ZIP contains headers, static libraries, `protoc`, `grpc_cpp_plugin`, license
files for gRPC and its bundled dependencies, a version stamp, and
`build_provenance.json`. Each adjacent JSON manifest records its SHA-256,
source/version stamp, and build-configuration key. The provenance records the
source revision, compiler banner, runner image, and CMake options.
The same provenance is exposed in adjacent `*.build.json` files for code review.

The initial packages were produced by [build run 42129354293](https://github.com/csc301-2026-f/20-AMD-Schola/actions/runs/42129354293).
Their manifests retain the original artifact hashes and record the pinned
utf8_range license added during packaging. This changes package checksums without
changing the compiled binaries.

Install the host package from the repository root:

```sh
uv run --no-project --python 3.12 python Godot/tools/setup_grpc.py
```

Installation checks the archive checksum, dependency pins, build configuration,
and required files before replacing `Godot/thirdparty/grpc/`. Linux generators
receive executable permissions after extraction. No CMake, compiler, or network
access is needed to install. Compiling Schola itself still needs a compiler.

A missing or incompatible package is an error. There is no automatic source-build
fallback that can unexpectedly add half an hour to ordinary CI. Other platforms
can use an explicit source build.

## Rebuilding

The **Rebuild vendored gRPC** workflow is manual-only. It builds both platforms
from the pinned source, verifies generation and static linking, and uploads ZIPs
and manifests as artifacts. Review and commit both platforms' packages and
manifests together after changing the pins or build options. Record the build run
in the dependency update PR. Artifacts are not automatically committed or promoted.
Future Windows rebuilds use Ninja with MSVC to schedule individual source files
in parallel; the initial Windows artifact used CMake's Visual Studio generator.

To rebuild locally with CMake and a compatible compiler:

```sh
uv run --no-project --python 3.12 python Godot/tools/setup_grpc.py --from-source --force
uv run --no-project --python 3.12 python Godot/tools/verify_grpc_package.py
uv run --no-project --python 3.12 python Godot/tools/package_grpc.py --output Godot/vendor/grpc
```

On Windows, run from an x64 Visual Studio Developer shell. A short dedicated
`--work-dir` avoids path-length failures. Source setup deletes and recreates that
directory, so it must not contain other work. The source-build path preserves the
existing macOS support; no macOS prebuilt package is committed.

## What stays in Actions caches

| Dependency or output | Storage |
| --- | --- |
| gRPC/protobuf headers, libraries, generators | ZIPs and checksum manifests in this directory |
| godot-cpp, Catch2, Schola compiled objects | SCons content cache, keyed by platform/compiler |
| ONNX Runtime | Pinned upstream prebuilt download, installed tree cached by Actions |
| Godot executable | Download cached by Actions; checksum verified on every run |
| GdUnit4 | Pinned upstream add-on, installed tree cached by Actions |
| Python build packages | Existing pip download cache |
| Generated protocol code, extensions, test executables | Generated during builds; not committed |

The SCons cache can restore older configurations because SCons checks each
output's input and build-command signatures before reuse. Installed dependency
caches have exact keys tied to the lock and installer, without stale fallbacks.
