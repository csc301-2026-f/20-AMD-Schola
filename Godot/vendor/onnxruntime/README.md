# Vendored ONNX Runtime 1.30.0

These CPU runtime packages are tracked with Git LFS so normal builds do not
depend on the availability of Microsoft's upstream repository. Install offline:

```sh
git lfs pull --include="Godot/vendor/onnxruntime/*.tar.gz" --exclude=""
python Godot/tools/setup_onnxruntime.py
```

The installer checks the package checksum, pinned version, required headers,
runtime and linker libraries, and license files before replacing the installed
tree. Missing archives and unfetched LFS pointers fail explicitly. There is no
network fallback. CI fetches only the package for its platform.

## Emergency recovery provenance

These are reconstructed dependency packages, not copies of the original upstream
release archives. The original download URLs and SHA-256 values remain in
`dependencies.lock.json` and each package manifest as historical records; they
cannot verify these repacked archives. Each adjacent JSON manifest records the
new archive checksum and per-file SHA-256 values for review.

- Windows x86_64: recovered from the existing local 1.30.0 installation,
  upstream commit `f2c39fe2f838cf35ce7da92824f5a5e3ee6e88a7`. PDB debug symbols
  were omitted; headers, runtime/import libraries, licenses, and notices remain.
- Linux x86_64 and macOS arm64: runtime libraries recovered from this project's
  [successful CI run 44039915487](https://github.com/csc301-2026-f/20-AMD-Schola/actions/runs/44039915487),
  artifacts `d3-package-linux-x86_64` and `d3-package-macos-arm64`. Each package
  includes `schola_recovery.json` recording the source artifact hash, member
  path, runtime hash, and the linker alias added during reconstruction. Public
  headers and notices come from the saved Windows 1.30.0 package. CI must verify
  compilation, linking, and runtime inference on each target before promotion.

The saved Windows installation and successful project artifacts provide recovery
provenance, not a fresh independent upstream verification. Version pins were not
changed. The original upstream archives were unavailable during recovery.

## Repackaging

Use a complete installation tree with `include/`, `lib/`, `VERSION_NUMBER`,
`LICENSE`, and `ThirdPartyNotices.txt`. Preserve provenance and licenses:

```sh
python Godot/tools/package_onnxruntime.py --source /path/to/install --host linux-x86_64 --provenance "Source artifact, run, and recovery details"
```

Review and commit the resulting archive and adjacent manifest together. The
packager does not build ONNX Runtime or download anything. Repacked archives
receive new hashes; do not substitute them for the historical upstream hashes.
