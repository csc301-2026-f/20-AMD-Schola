#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import argparse
import json
import tarfile
import tempfile
import zipfile
from pathlib import Path

from setup_onnxruntime import LOCK_FILE, VENDOR_DIRECTORY, sha256


def package(nuget_path, host):
    dependency = json.loads(LOCK_FILE.read_text(encoding="utf-8"))["onnxruntime"]
    source = dependency["source_package"]
    if sha256(nuget_path) != source["sha256"]:
        raise RuntimeError("NuGet package checksum does not match the verified source")
    runtime_id = {
        "windows-x86_64": "win-x64",
        "linux-x86_64": "linux-x64",
        "macos-arm64": "osx-arm64",
    }[host]
    VENDOR_DIRECTORY.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=VENDOR_DIRECTORY) as temporary:
        root = Path(temporary)
        source_members = {}
        with zipfile.ZipFile(nuget_path) as nuget:
            for member in nuget.namelist():
                if member.startswith("build/native/include/"):
                    relative = "include/" + member.removeprefix("build/native/include/")
                elif member.startswith(f"runtimes/{runtime_id}/native/"):
                    relative = "lib/" + member.removeprefix(
                        f"runtimes/{runtime_id}/native/"
                    )
                elif member in (
                    "LICENSE",
                    "ThirdPartyNotices.txt",
                    "Privacy.md",
                    "README.md",
                ):
                    relative = member
                else:
                    continue
                if member.endswith("/"):
                    continue
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(nuget.read(member))
                source_members[relative] = member
            aliases = {
                "linux-x86_64": ("libonnxruntime.so", "libonnxruntime.so.1"),
                "macos-arm64": ("libonnxruntime.dylib", "libonnxruntime.1.dylib"),
            }
            if host in aliases:
                original, alias = aliases[host]
                (root / "lib" / alias).write_bytes(
                    (root / "lib" / original).read_bytes()
                )
                source_members[f"lib/{alias}"] = source_members[f"lib/{original}"]
        (root / "VERSION_NUMBER").write_text(dependency["version"] + "\n")
        (root / "GIT_COMMIT_ID").write_text(source["commit"] + "\n")
        filename = f"{host}.tar.gz"
        archive_path = VENDOR_DIRECTORY / filename
        files = {}
        with tarfile.open(archive_path, "w:gz", compresslevel=9) as archive:
            for path in sorted(root.rglob("*")):
                relative = path.relative_to(root).as_posix()
                archive.add(path, arcname=f"onnxruntime/{relative}", recursive=False)
                if path.is_file():
                    files[relative] = sha256(path)
        manifest = {
            "file": filename,
            "sha256": sha256(archive_path),
            "host": host,
            "version": dependency["version"],
            "source_package": source,
            "source_members": source_members,
            "generated_metadata": ["VERSION_NUMBER", "GIT_COMMIT_ID"],
            "files": files,
        }
        (VENDOR_DIRECTORY / f"{host}.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        print(f"Packaged {archive_path}: {manifest['sha256']}")


def main():
    parser = argparse.ArgumentParser(
        description="Repack the verified ONNX NuGet package"
    )
    parser.add_argument("--nuget", type=Path, required=True)
    parser.add_argument(
        "--host",
        choices=("windows-x86_64", "linux-x86_64", "macos-arm64"),
        required=True,
    )
    args = parser.parse_args()
    package(args.nuget, args.host)


if __name__ == "__main__":
    main()
