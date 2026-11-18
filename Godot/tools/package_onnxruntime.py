#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import argparse
import json
import tarfile
from pathlib import Path

from setup_onnxruntime import LOCK_FILE, VENDOR_DIRECTORY, sha256


def main():
    parser = argparse.ArgumentParser(
        description="Package a recovered ONNX installation"
    )
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--provenance", required=True)
    args = parser.parse_args()
    dependency = json.loads(LOCK_FILE.read_text())["onnxruntime"]
    if args.host not in dependency["archives"]:
        parser.error("Host is not pinned in dependencies.lock.json")
    if (args.source / "VERSION_NUMBER").read_text().strip() != dependency["version"]:
        parser.error("Recovered installation version does not match the lock")
    for name in ("include/onnxruntime_c_api.h", "LICENSE", "ThirdPartyNotices.txt"):
        if not (args.source / name).is_file():
            parser.error(f"Missing {name}")
    VENDOR_DIRECTORY.mkdir(parents=True, exist_ok=True)
    filename = f"{args.host}.tar.gz"
    archive_path = VENDOR_DIRECTORY / filename
    files = {}
    with tarfile.open(archive_path, "w:gz", compresslevel=9) as archive:
        for path in sorted(args.source.rglob("*")):
            # Debug symbols are not needed to compile, link, or run Schola.
            if path.suffix.lower() == ".pdb":
                continue
            relative = path.relative_to(args.source).as_posix()
            archive.add(path, arcname=f"onnxruntime/{relative}", recursive=False)
            if path.is_file():
                files[relative] = sha256(path)
    manifest = {
        "file": filename,
        "sha256": sha256(archive_path),
        "host": args.host,
        "version": dependency["version"],
        "upstream_archive": dependency["archives"][args.host],
        "provenance": args.provenance,
        "files": files,
    }
    (VENDOR_DIRECTORY / f"{args.host}.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Packaged {archive_path}: {manifest['sha256']}")


if __name__ == "__main__":
    main()
