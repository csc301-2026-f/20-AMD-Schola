#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

"""Package an explicitly rebuilt gRPC install for review and vendoring."""

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
from pathlib import Path

import setup_grpc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    system, machine = setup_grpc.host()
    lock = json.loads(setup_grpc.LOCK_FILE.read_text(encoding="utf-8"))
    compiler = ["cl"] if system == "windows" else ["c++", "--version"]
    version = subprocess.run(compiler, capture_output=True, text=True)
    provenance = {
        "source_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], text=True
        ).strip(),
        "runner_image": os.environ.get("ImageOS"),
        "runner_image_version": os.environ.get("ImageVersion"),
        "platform": platform.platform(),
        "build_generator": os.environ.get("CMAKE_GENERATOR", "CMake platform default"),
        "compiler": (version.stdout + version.stderr).strip(),
        "configuration_key": setup_grpc.cache_key(
            lock["grpc"], lock["protobuf"], system, machine
        ),
        "configuration": [
            str(value)
            for value in setup_grpc.configure_arguments(
                system, machine, Path("source"), Path("build"), Path("install")
            )
        ],
    }
    root = setup_grpc.INSTALL_DIRECTORY
    (root / "build_provenance.json").write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )
    arguments.output.mkdir(parents=True, exist_ok=True)
    name = f"{system}-{machine}"
    (arguments.output / f"{name}.build.json").write_text(
        json.dumps(provenance, indent=2) + "\n", encoding="utf-8"
    )
    archive = Path(shutil.make_archive(str(arguments.output / name), "zip", root))
    with archive.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    manifest = {
        "file": archive.name,
        "sha256": digest,
        "configuration_key": provenance["configuration_key"],
        "stamp": setup_grpc.expected_stamp(
            lock["grpc"], lock["protobuf"], system, machine
        ),
    }
    (arguments.output / f"{name}.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Packaged {archive} ({archive.stat().st_size} bytes), sha256={digest}")


if __name__ == "__main__":
    main()
