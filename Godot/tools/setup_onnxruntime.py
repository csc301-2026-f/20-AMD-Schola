#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import hashlib
import json
import platform
import shutil
import tarfile
import tempfile
import zipfile
from pathlib import Path

GODOT_ROOT = Path(__file__).resolve().parents[1]
LOCK_FILE = GODOT_ROOT / "dependencies.lock.json"
INSTALL_DIRECTORY = GODOT_ROOT / "thirdparty" / "onnxruntime"
VENDOR_DIRECTORY = GODOT_ROOT / "vendor" / "onnxruntime"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as archive:
        for block in iter(lambda: archive.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def host_platform():
    system = {"Windows": "windows", "Linux": "linux", "Darwin": "macos"}.get(
        platform.system()
    )
    machine = {
        "AMD64": "x86_64",
        "x86_64": "x86_64",
        "arm64": "arm64",
        "aarch64": "arm64",
    }.get(platform.machine())
    if system is None or machine is None:
        raise RuntimeError(
            f"Unsupported host: {platform.system()} {platform.machine()}"
        )
    return f"{system}-{machine}"


def extract(archive_path, destination):
    if archive_path.name.endswith(".zip"):
        with zipfile.ZipFile(archive_path) as archive:
            if any(
                Path(name).is_absolute()
                or ".." in Path(name).parts
                or ":" in name
                or "\\" in name
                for name in archive.namelist()
            ):
                raise RuntimeError("ONNX Runtime archive contains an unsafe path")
            archive.extractall(destination)
    else:
        with tarfile.open(archive_path) as archive:
            archive.extractall(destination, filter="data")


def install_onnxruntime(archive_path, archive, host=None, version=None):
    expected_hash = archive["sha256"]
    actual_hash = sha256(archive_path)
    if actual_hash != expected_hash:
        raise RuntimeError(
            f"ONNX Runtime archive checksum mismatch: expected {expected_hash}, got {actual_hash}"
        )

    with tempfile.TemporaryDirectory(dir=GODOT_ROOT) as temporary_directory:
        staged_directory = Path(temporary_directory)
        extract(archive_path, staged_directory)
        roots = [path for path in staged_directory.iterdir() if path.is_dir()]
        if (
            len(roots) != 1
            or not (roots[0] / "include" / "onnxruntime_c_api.h").is_file()
        ):
            raise RuntimeError("ONNX Runtime archive does not have the expected layout")

        if version is not None:
            root = roots[0]
            if (root / "VERSION_NUMBER").read_text().strip() != version:
                raise RuntimeError(
                    "ONNX Runtime package version does not match the lock"
                )
            required = {
                "windows-x86_64": ["onnxruntime.dll", "onnxruntime.lib"],
                "linux-x86_64": ["libonnxruntime.so", "libonnxruntime.so.1"],
                "macos-arm64": ["libonnxruntime.dylib", "libonnxruntime.1.dylib"],
            }[host]
            if any(not (root / "lib" / name).is_file() for name in required):
                raise RuntimeError("ONNX Runtime package is missing required libraries")
            for name in ("LICENSE", "ThirdPartyNotices.txt"):
                if not (root / name).is_file():
                    raise RuntimeError(f"ONNX Runtime package is missing {name}")

        if INSTALL_DIRECTORY.exists():
            shutil.rmtree(INSTALL_DIRECTORY)
        INSTALL_DIRECTORY.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(roots[0], INSTALL_DIRECTORY)


def main():
    dependency = json.loads(LOCK_FILE.read_text(encoding="utf-8"))["onnxruntime"]
    host = host_platform()
    archive = dependency["archives"].get(host)
    if archive is None:
        raise RuntimeError(f"No pinned ONNX Runtime archive for {host}")

    manifest_path = VENDOR_DIRECTORY / f"{host}.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"No committed ONNX Runtime package for {host}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["version"] != dependency["version"] or manifest["host"] != host:
        raise RuntimeError(
            "ONNX Runtime package manifest does not match dependency pins"
        )
    if manifest["file"] != f"{host}.tar.gz":
        raise RuntimeError("Unexpected ONNX Runtime package filename")
    archive_path = VENDOR_DIRECTORY / manifest["file"]
    if not archive_path.is_file():
        raise RuntimeError(f"Missing committed ONNX Runtime archive: {archive_path}")
    with archive_path.open("rb") as source:
        if source.read(64).startswith(b"version https://git-lfs.github.com/spec/v1"):
            raise RuntimeError(
                "ONNX Runtime package is a Git LFS pointer. Run git lfs pull "
                '--include="Godot/vendor/onnxruntime/*.tar.gz" --exclude="" first.'
            )
    install_onnxruntime(archive_path, manifest, host, dependency["version"])
    print(f"Installed ONNX Runtime {dependency['version']} to {INSTALL_DIRECTORY}")


if __name__ == "__main__":
    main()
