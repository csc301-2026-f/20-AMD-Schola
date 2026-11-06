#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import argparse
import hashlib
import json
import os
import platform
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path

GODOT_ROOT = Path(__file__).resolve().parents[1]
LOCK_FILE = GODOT_ROOT / "dependencies.lock.json"
INSTALL_DIRECTORY = GODOT_ROOT / "thirdparty" / "grpc"
VENDOR_DIRECTORY = GODOT_ROOT / "vendor" / "grpc"
# Read by SConstruct to detect an install that no longer matches the lock.
STAMP_FILENAME = "schola_grpc.json"
# Only the submodules the CMake build uses with every provider set to "module".
SUBMODULES = (
    "third_party/abseil-cpp",
    "third_party/boringssl-with-bazel",
    "third_party/cares/cares",
    "third_party/protobuf",
    "third_party/re2",
    "third_party/zlib",
)


def host():
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
    return system, machine


def run(arguments, working_directory=None):
    print("+", " ".join(str(argument) for argument in arguments), flush=True)
    subprocess.run(
        [str(argument) for argument in arguments], check=True, cwd=working_directory
    )


def remove_directory(directory):
    def retry_read_only(function, path, exception_info):
        error = exception_info[1]
        if not isinstance(error, PermissionError):
            raise error
        mode = os.stat(path).st_mode
        if mode & stat.S_IWRITE:
            raise error
        # Git pack files are read-only on Windows, even in our own checkout.
        os.chmod(path, mode | stat.S_IWRITE)
        function(path)

    shutil.rmtree(directory, onerror=retry_read_only)


def expected_stamp(grpc, protobuf, system, machine):
    return {
        "grpc_tag": grpc["tag"],
        "grpc_commit": grpc["commit"],
        "protobuf_version": protobuf["version"],
        "platform": system,
        "arch": machine,
    }


def cache_key(grpc, protobuf, system, machine):
    # Covers what decides this platform's install, so CI keeps its cached build when
    # only another platform's options or the script's other code change.
    configuration = {
        "stamp": expected_stamp(grpc, protobuf, system, machine),
        "submodules": list(SUBMODULES),
        "configure": [
            str(argument)
            for argument in configure_arguments(
                system, machine, Path("source"), Path("build"), Path("install")
            )
        ],
    }
    encoded = json.dumps(configuration, sort_keys=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:16]


def installed_stamp():
    stamp_path = INSTALL_DIRECTORY / STAMP_FILENAME
    if not stamp_path.is_file():
        return None
    return json.loads(stamp_path.read_text(encoding="utf-8"))


def install_prebuilt(grpc, protobuf, system, machine):
    name = f"{system}-{machine}"
    manifest_path = VENDOR_DIRECTORY / f"{name}.json"
    if not manifest_path.is_file():
        raise RuntimeError(
            f"No committed gRPC package for {name}. Use --from-source to rebuild explicitly."
        )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["file"] != f"{name}.zip":
        raise RuntimeError("Unexpected gRPC archive filename")
    expected = expected_stamp(grpc, protobuf, system, machine)
    configuration = cache_key(grpc, protobuf, system, machine)
    if manifest["stamp"] != expected or manifest["configuration_key"] != configuration:
        raise RuntimeError(
            "Committed gRPC package does not match dependency pins or build options; rebuild it."
        )
    archive_path = VENDOR_DIRECTORY / manifest["file"]
    with archive_path.open("rb") as source:
        if source.read(64).startswith(b"version https://git-lfs.github.com/spec/v1"):
            raise RuntimeError(
                "gRPC package is a Git LFS pointer. Run git lfs pull "
                '--include="Godot/vendor/grpc/*.zip" --exclude="" first.'
            )
        source.seek(0)
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    if digest != manifest["sha256"]:
        raise RuntimeError("Committed gRPC archive checksum mismatch")
    INSTALL_DIRECTORY.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix="grpc-install-", dir=INSTALL_DIRECTORY.parent
    ) as temporary:
        staged = Path(temporary) / "install"
        with zipfile.ZipFile(archive_path) as archive:
            for entry in archive.infolist():
                path = Path(entry.filename)
                if (
                    path.is_absolute()
                    or ".." in path.parts
                    or ":" in entry.filename
                    or "\\" in entry.filename
                    or stat.S_ISLNK(entry.external_attr >> 16)
                ):
                    raise RuntimeError("gRPC archive contains an unsafe path")
            archive.extractall(staged)
        if (
            json.loads((staged / STAMP_FILENAME).read_text(encoding="utf-8"))
            != expected
        ):
            raise RuntimeError("gRPC archive stamp does not match the pinned release")
        provenance = json.loads(
            (staged / "build_provenance.json").read_text(encoding="utf-8")
        )
        if provenance["configuration_key"] != configuration:
            raise RuntimeError(
                "gRPC archive provenance does not match its build configuration"
            )
        suffix = ".exe" if system == "windows" else ""
        required = [
            "include/grpcpp/grpcpp.h",
            "include/google/protobuf/message.h",
            f"bin/protoc{suffix}",
            f"bin/grpc_cpp_plugin{suffix}",
        ]
        if any(not (staged / path).is_file() for path in required) or not any(
            (staged / "lib").glob("*.lib" if system == "windows" else "*.a")
        ):
            raise RuntimeError(
                "gRPC archive is missing required headers, libraries, or generators"
            )
        for tool in ("protoc", "grpc_cpp_plugin"):
            if system != "windows":
                (staged / "bin" / tool).chmod(0o755)
        if INSTALL_DIRECTORY.exists():
            remove_directory(INSTALL_DIRECTORY)
        shutil.move(str(staged), str(INSTALL_DIRECTORY))
    print(
        f"Installed committed gRPC package for {name}; no source build or download needed."
    )


def checkout(grpc, protobuf, source_directory):
    run(
        [
            "git",
            "clone",
            "--branch",
            grpc["tag"],
            "--depth",
            "1",
            "--single-branch",
            grpc["url"],
            source_directory,
        ]
    )
    commit = subprocess.run(
        ["git", "-C", str(source_directory), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if commit != grpc["commit"]:
        raise RuntimeError(
            f"gRPC {grpc['tag']} resolved to {commit}, but the lock pins {grpc['commit']}"
        )
    run(
        [
            "git",
            "-C",
            source_directory,
            "submodule",
            "update",
            "--init",
            "--depth",
            "1",
            "--",
        ]
        + list(SUBMODULES)
    )

    # Protobuf comes from the gRPC submodule; check it is the locked release.
    version_file = source_directory / "third_party" / "protobuf" / "version.json"
    versions = json.loads(version_file.read_text(encoding="utf-8"))
    protoc_versions = {entry.get("protoc_version") for entry in versions.values()}
    if protobuf["version"] not in protoc_versions:
        raise RuntimeError(
            f"gRPC {grpc['tag']} bundles protobuf {sorted(protoc_versions)}, but the lock pins {protobuf['version']}"
        )


def configure_arguments(
    system, machine, source_directory, build_directory, install_directory
):
    arguments = [
        "cmake",
        "-S",
        source_directory,
        "-B",
        build_directory,
        "-DCMAKE_BUILD_TYPE=Release",
        f"-DCMAKE_INSTALL_PREFIX={install_directory}",
        "-DCMAKE_INSTALL_LIBDIR=lib",
        # Matches godot-cpp, so Abseil's std:: type aliases agree with the extension.
        "-DCMAKE_CXX_STANDARD=17",
        "-DABSL_PROPAGATE_CXX_STD=ON",
        # The archives are linked into a shared GDExtension library.
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
        "-DBUILD_SHARED_LIBS=OFF",
        # Keeps gRPC and protobuf symbols private to the training extension.
        "-DCMAKE_C_VISIBILITY_PRESET=hidden",
        "-DCMAKE_CXX_VISIBILITY_PRESET=hidden",
        "-DCMAKE_VISIBILITY_INLINES_HIDDEN=ON",
        "-DgRPC_INSTALL=ON",
        "-DgRPC_BUILD_TESTS=OFF",
        "-DgRPC_BUILD_CODEGEN=ON",
        "-DgRPC_BUILD_GRPC_CPP_PLUGIN=ON",
        "-DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF",
        "-DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF",
        "-DgRPC_BUILD_CSHARP_EXT=OFF",
        "-DgRPC_USE_SYSTEMD=OFF",
        "-DgRPC_ABSL_PROVIDER=module",
        "-DgRPC_CARES_PROVIDER=module",
        "-DgRPC_PROTOBUF_PROVIDER=module",
        "-DgRPC_RE2_PROVIDER=module",
        "-DgRPC_SSL_PROVIDER=module",
        "-DgRPC_ZLIB_PROVIDER=module",
        "-Dprotobuf_BUILD_TESTS=OFF",
        "-DRE2_BUILD_TESTING=OFF",
        "-DCARES_BUILD_TOOLS=OFF",
        # The examples link zlib's shared library, which exports nothing with
        # hidden visibility.
        "-DZLIB_BUILD_EXAMPLES=OFF",
        # gRPC installs the static zlib itself. zlib's own rule would also install
        # its shared library, which linkers prefer over the archive.
        "-DSKIP_INSTALL_LIBRARIES=ON",
    ]
    if system == "macos":
        arguments.append(f"-DCMAKE_OSX_ARCHITECTURES={machine}")
    elif system == "windows":
        arguments += [
            # godot-cpp links the static MSVC runtime (/MT) by default.
            "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded",
            "-DgRPC_MSVC_STATIC_RUNTIME=ON",
            "-DCARES_MSVC_STATIC_RUNTIME=ON",
            "-Dprotobuf_MSVC_STATIC_RUNTIME=ON",
            "-DABSL_MSVC_STATIC_RUNTIME=ON",
            # BoringSSL's assembly needs NASM; the connector never uses TLS.
            "-DOPENSSL_NO_ASM=ON",
        ]
    return arguments


def build(grpc, protobuf, system, machine, work_directory):
    source_directory = work_directory / "source"
    build_directory = work_directory / "build"
    staged_directory = work_directory / "install"

    checkout(grpc, protobuf, source_directory)
    run(
        configure_arguments(
            system, machine, source_directory, build_directory, staged_directory
        )
    )
    run(
        [
            "cmake",
            "--build",
            build_directory,
            "--config",
            "Release",
            "--parallel",
            str(os.cpu_count() or 2),
        ]
    )
    run(["cmake", "--install", build_directory, "--config", "Release"])

    for component in (
        (".",) + SUBMODULES + ("third_party/protobuf/third_party/utf8_range",)
    ):
        directory = source_directory / component
        for license_file in directory.iterdir():
            if license_file.is_file() and license_file.name.upper().startswith(
                ("LICENSE", "COPYING", "NOTICE")
            ):
                destination = (
                    staged_directory / "licenses" / component / license_file.name
                )
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(license_file, destination)

    stamp = expected_stamp(grpc, protobuf, system, machine)
    (staged_directory / STAMP_FILENAME).write_text(
        json.dumps(stamp, indent=2) + "\n", encoding="utf-8"
    )
    if INSTALL_DIRECTORY.exists():
        remove_directory(INSTALL_DIRECTORY)
    INSTALL_DIRECTORY.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(staged_directory), str(INSTALL_DIRECTORY))


def main():
    parser = argparse.ArgumentParser(
        description="Install committed gRPC/protobuf into Godot/thirdparty/grpc/; source builds are opt-in."
    )
    parser.add_argument(
        "--from-source",
        action="store_true",
        help="Explicitly rebuild instead of installing the committed prebuilt package.",
    )
    parser.add_argument(
        "--work-dir",
        type=Path,
        help="Directory for the source checkout and build tree. Defaults to a temporary "
        "directory that is removed afterwards. On Windows, a short path such as C:\\grpc "
        "avoids MAX_PATH failures.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Rebuild even if the pinned release is installed.",
    )
    parser.add_argument(
        "--print-cache-key",
        action="store_true",
        help="Print the CI cache key for this host's build and exit without building.",
    )
    arguments = parser.parse_args()

    dependencies = json.loads(LOCK_FILE.read_text(encoding="utf-8"))
    grpc = dependencies["grpc"]
    protobuf = dependencies["protobuf"]
    system, machine = host()

    if arguments.print_cache_key:
        print(cache_key(grpc, protobuf, system, machine))
        return

    if not arguments.from_source:
        if arguments.force or arguments.work_dir is not None:
            parser.error("--force and --work-dir require --from-source")
        install_prebuilt(grpc, protobuf, system, machine)
        return

    if shutil.which("cmake") is None:
        raise RuntimeError("CMake 3.16 or newer is required to build gRPC")

    if not arguments.force and installed_stamp() == expected_stamp(
        grpc, protobuf, system, machine
    ):
        print(f"gRPC {grpc['tag']} is already installed in {INSTALL_DIRECTORY}")
        return

    if arguments.work_dir is None:
        with tempfile.TemporaryDirectory(prefix="schola-grpc-") as temporary_directory:
            build(grpc, protobuf, system, machine, Path(temporary_directory))
    else:
        work_directory = arguments.work_dir.resolve()
        if work_directory.exists():
            remove_directory(work_directory)
        work_directory.mkdir(parents=True)
        build(grpc, protobuf, system, machine, work_directory)
    print(
        f"Installed gRPC {grpc['tag']} with protobuf {protobuf['version']} to {INSTALL_DIRECTORY}"
    )


if __name__ == "__main__":
    main()
