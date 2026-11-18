# Vendored ONNX Runtime 1.30.0

These CPU runtime packages are tracked with Git LFS so builds do not depend on
Microsoft's GitHub repository. Every native library, header, license, notice,
and README is copied byte-for-byte from the hash-pinned, signature-verified
`Microsoft.ML.OnnxRuntime` 1.30.0 NuGet package. See [verification evidence](VERIFICATION.md).

```sh
git lfs pull --include="Godot/vendor/onnxruntime/*.tar.gz" --exclude=""
python Godot/tools/setup_onnxruntime.py
```

Installation is offline and checks the archive SHA-256, pinned version, required
headers, runtime/linker libraries, and license files before replacing the install.
Missing packages and unfetched LFS pointers fail explicitly. CI fetches only its
platform's package. The upstream GitHub archive URLs/hashes in the lockfile are
historical records; the new archive hashes are in the adjacent package manifests.

## Verified source and packaging

The common source for Windows x86_64, Linux x86_64, and macOS arm64 is Microsoft's
[NuGet package](https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime/1.30.0).
Its author and repository signatures were verified with NuGet 6.14.0. Its source
URL, SHA-256 and upstream revision are pinned in `dependencies.lock.json`.

The packages contain no locally recovered binary payloads. Unix linker/runtime
aliases are duplicate copies of the same signed-source library. `VERSION_NUMBER`
and `GIT_COMMIT_ID` are generated from the pinned source metadata. Every other
file has a source ZIP member recorded in its manifest. No binary contents or
code signatures are patched. Managed .NET, mobile, and unrelated platform assets
are omitted because Schola uses the native C API.

To reproduce the payloads, download the pinned NuGet package, verify its
signatures, then run for each host (`windows-x86_64`, `linux-x86_64`, `macos-arm64`):

```sh
nuget verify -All microsoft.ml.onnxruntime.1.30.0.nupkg -Verbosity detailed
python Godot/tools/package_onnxruntime.py --nuget microsoft.ml.onnxruntime.1.30.0.nupkg --host linux-x86_64
python Godot/tools/verify_onnxruntime_source.py --nuget microsoft.ml.onnxruntime.1.30.0.nupkg
```

The packager and verifier reject a NuGet package whose SHA-256 differs from the
verified pinned source. The verifier compares every payload byte directly to its
source member and checks generated metadata, archive inventories, and hashes.
Tar/gzip timestamps can change the outer archive hash on repackaging; compare
payloads and update adjacent manifests together. No network fallback runs during
normal installation.
