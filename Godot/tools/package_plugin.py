# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
"""Package the runtime and editor add-on for installation in a Godot project."""

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


def package(repository: Path, platform: str, arch: str, output: Path) -> None:
    addon = repository / "Godot/addons/schola"
    suffix = {"windows": "dll", "linux": "so", "macos": "dylib"}[platform]
    prefix = "" if platform == "windows" else "lib"
    binaries = addon / "bin" / platform
    required = [
        binaries / f"{prefix}schola.{platform}.{target}.{arch}.{suffix}"
        for target in ("template_debug", "template_release")
    ]
    dependency = {
        "windows": "onnxruntime.dll",
        "linux": "libonnxruntime.so.1",
        "macos": "libonnxruntime.1.dylib",
    }[platform]
    required.append(binaries / dependency)
    notices = repository / "Godot/thirdparty/onnxruntime"
    required.extend(notices / name for name in ("LICENSE", "ThirdPartyNotices.txt"))
    required.extend(
        addon / name
        for name in (
            "plugin.cfg",
            "schola.gdextension",
            "schola_plugin.gd",
            "space_inspector.gd",
            "ui/schola_monitor.gd",
        )
    )
    for path in required:
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(f"Missing or empty package input: {path}")
    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repository, text=True
    ).strip()
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary)
        destination = stage / "addons/schola"
        destination.mkdir(parents=True)
        for path in required:
            if path.is_relative_to(addon):
                target = destination / path.relative_to(addon)
            else:
                target = stage / "licenses/onnxruntime" / path.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        for path in addon.rglob("*"):
            if (
                path.is_file()
                and "bin" not in path.relative_to(addon).parts
                and path.suffix in (".gd", ".gdshader", ".uid")
            ):
                target = destination / path.relative_to(addon)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        # Include additional versioned runtime libraries used by the loader.
        for path in binaries.glob(f"*onnxruntime*.{suffix}*"):
            if path.is_file():
                shutil.copyfile(path, destination / "bin" / platform / path.name)
        (stage / "licenses/godot-cpp").mkdir(parents=True)
        shutil.copyfile(
            repository / "Godot/godot-cpp/LICENSE.md",
            stage / "licenses/godot-cpp/LICENSE.md",
        )
        shutil.copyfile(repository / "LICENSE.txt", stage / "LICENSE.txt")
        guide = (repository / "Godot/docs/distribution.md").read_text(encoding="utf-8")
        guide = guide.replace(
            "(../README.md",
            f"(https://github.com/csc301-2026-f/20-AMD-Schola/blob/{revision}/Godot/README.md",
        )
        (stage / "INSTALL.md").write_text(guide, encoding="utf-8")
        (stage / "BUILD.txt").write_text(
            f"commit={revision}\nplatform={platform}\narch={arch}\n"
            "contents=runtime and editor add-on; training extension excluded\n",
            encoding="utf-8",
        )
        output.parent.mkdir(parents=True, exist_ok=True)
        with ZipFile(output, "w", ZIP_DEFLATED) as archive:
            for path in sorted(stage.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(stage).as_posix())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--platform", choices=("windows", "linux", "macos"), required=True
    )
    parser.add_argument("--arch", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    package(
        Path(__file__).resolve().parents[2],
        arguments.platform,
        arguments.arch,
        arguments.output,
    )
