# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
"""Package the runtime/editor add-on and training on supported platforms."""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


def package(repository: Path, platform: str, arch: str, output: Path) -> None:
    addons = repository / "Godot/addons"
    addon = addons / "schola"
    include_training = (platform, arch) in {("linux", "x86_64"), ("windows", "x86_64")}
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
    if include_training:
        training = addons / "schola_training"
        required.append(training / "schola_training.gdextension")
        training_binaries = training / "bin" / platform
        required.extend(
            training_binaries
            / f"{prefix}schola_training.{platform}.{target}.{arch}.{suffix}"
            for target in ("template_debug", "template_release")
        )
    for path in required:
        if not path.is_file() or path.stat().st_size == 0:
            raise FileNotFoundError(f"Missing or empty package input: {path}")
    revision = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=repository, text=True
    ).strip()
    with tempfile.TemporaryDirectory() as temporary:
        stage = Path(temporary) / "archive"
        destination = stage / "addons/schola"
        destination.mkdir(parents=True)
        for path in required:
            if path.is_relative_to(addons):
                target = stage / "addons" / path.relative_to(addons)
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
        contents = "runtime and editor add-on"
        if include_training:
            shutil.copytree(
                repository / "Godot/thirdparty/grpc/licenses", stage / "licenses/grpc"
            )
            # Build only the shared client, without neighboring packages or local
            # setuptools build outputs in the source checkout.
            python_source = repository / "Resources/python"
            wheel_source = Path(temporary) / "python-source"
            shutil.copytree(
                python_source / "schola",
                wheel_source / "schola",
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
            )
            for name in ("pyproject.toml", "README.md", "LICENSE.txt"):
                shutil.copyfile(python_source / name, wheel_source / name)
            subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "pip",
                    "wheel",
                    "--no-deps",
                    "--wheel-dir",
                    str(stage / "python"),
                    str(wheel_source),
                ],
                check=True,
            )
            contents += "; training extension and Schola Python wheel"
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
            f"contents={contents}\n",
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
