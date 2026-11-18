#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import argparse
import hashlib
import json
import tarfile
import zipfile
from pathlib import Path

from setup_onnxruntime import LOCK_FILE, VENDOR_DIRECTORY, sha256


def verify(nuget_path):
    dependency = json.loads(LOCK_FILE.read_text(encoding="utf-8"))["onnxruntime"]
    source = dependency["source_package"]
    if sha256(nuget_path) != source["sha256"]:
        raise RuntimeError("NuGet package does not match the verified source hash")
    with zipfile.ZipFile(nuget_path) as nuget:
        for host in dependency["archives"]:
            manifest = json.loads((VENDOR_DIRECTORY / f"{host}.json").read_text())
            if manifest["source_package"] != source:
                raise RuntimeError(f"{host}: source provenance differs from lock")
            archive_path = VENDOR_DIRECTORY / manifest["file"]
            if sha256(archive_path) != manifest["sha256"]:
                raise RuntimeError(f"{host}: archive hash differs from manifest")
            actual_files = set()
            with tarfile.open(archive_path) as archive:
                for member in archive:
                    if member.isdir():
                        continue
                    if not member.isfile() or not member.name.startswith(
                        "onnxruntime/"
                    ):
                        raise RuntimeError(f"{host}: unexpected archive entry")
                    name = member.name.removeprefix("onnxruntime/")
                    if name in actual_files:
                        raise RuntimeError(f"{host}: duplicate archive entry {name}")
                    actual_files.add(name)
                    data = archive.extractfile(member).read()
                    if hashlib.sha256(data).hexdigest() != manifest["files"][name]:
                        raise RuntimeError(f"{host}: per-file hash mismatch for {name}")
                    if name in manifest["source_members"]:
                        original = nuget.read(manifest["source_members"][name])
                        if data != original:
                            raise RuntimeError(
                                f"{host}: {name} differs from signed source"
                            )
                    elif name == "VERSION_NUMBER":
                        if data.decode().strip() != dependency["version"]:
                            raise RuntimeError(f"{host}: wrong generated version")
                    elif name == "GIT_COMMIT_ID":
                        if data.decode().strip() != source["commit"]:
                            raise RuntimeError(f"{host}: wrong generated commit")
                    else:
                        raise RuntimeError(
                            f"{host}: file has no verified source: {name}"
                        )
            if actual_files != set(manifest["files"]):
                raise RuntimeError(f"{host}: manifest inventory differs from archive")
            print(
                f"{host}: {len(actual_files)} files verified; all payload bytes match signed NuGet source"
            )


def main():
    parser = argparse.ArgumentParser(
        description="Compare vendored ONNX payloads to the verified NuGet package"
    )
    parser.add_argument("--nuget", type=Path, required=True)
    args = parser.parse_args()
    verify(args.nuget)


if __name__ == "__main__":
    main()
