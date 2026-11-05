# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import os
import hashlib
import json
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import setup_grpc


class PrebuiltGrpcTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.vendor = self.root / "vendor"
        self.vendor.mkdir()
        self.install = self.root / "thirdparty" / "grpc"
        self.install.mkdir(parents=True)
        (self.install / "existing").write_text("previous install")
        self.grpc = {"tag": "v1.80.0", "commit": "f5e2d6e"}
        self.protobuf = {"version": "31.1"}
        self.stamp = setup_grpc.expected_stamp(
            self.grpc, self.protobuf, "linux", "x86_64"
        )
        self.configuration = setup_grpc.cache_key(
            self.grpc, self.protobuf, "linux", "x86_64"
        )
        self.archive = self.vendor / "linux-x86_64.zip"
        self.entries = {
            setup_grpc.STAMP_FILENAME: json.dumps(self.stamp),
            "build_provenance.json": json.dumps(
                {"configuration_key": self.configuration}
            ),
            "include/grpcpp/grpcpp.h": "header",
            "include/google/protobuf/message.h": "header",
            "lib/libgrpc.a": "library",
            "bin/protoc": "generator",
            "bin/grpc_cpp_plugin": "generator",
        }
        self.write_package()
        for name, value in (
            ("VENDOR_DIRECTORY", self.vendor),
            ("INSTALL_DIRECTORY", self.install),
        ):
            patcher = patch.object(setup_grpc, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def write_package(self):
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name, value in self.entries.items():
                archive.writestr(name, value)
        self.manifest = {
            "file": self.archive.name,
            "stamp": self.stamp,
            "configuration_key": self.configuration,
            "sha256": hashlib.sha256(self.archive.read_bytes()).hexdigest(),
        }
        self.write_manifest()

    def write_manifest(self):
        (self.vendor / "linux-x86_64.json").write_text(json.dumps(self.manifest))

    def install_package(self):
        setup_grpc.install_prebuilt(self.grpc, self.protobuf, "linux", "x86_64")

    def test_valid_package_replaces_install_without_building(self):
        with patch.object(
            setup_grpc, "run", side_effect=AssertionError("must not compile")
        ):
            self.install_package()
        self.assertFalse((self.install / "existing").exists())
        self.assertEqual((self.install / "bin/protoc").read_text(), "generator")

    def test_corrupt_archive_preserves_previous_install(self):
        self.archive.write_bytes(b"corrupt")
        with self.assertRaisesRegex(RuntimeError, "checksum"):
            self.install_package()
        self.assertTrue((self.install / "existing").exists())

    def test_changed_pins_require_an_explicit_rebuild(self):
        with self.assertRaisesRegex(RuntimeError, "pins or build options"):
            setup_grpc.install_prebuilt(
                {**self.grpc, "commit": "new"}, self.protobuf, "linux", "x86_64"
            )
        self.assertTrue((self.install / "existing").exists())

    def test_unsafe_archive_preserves_previous_install(self):
        self.entries["../escaped"] = "unsafe"
        self.write_package()
        with self.assertRaisesRegex(RuntimeError, "unsafe path"):
            self.install_package()
        self.assertFalse((self.root / "thirdparty/escaped").exists())
        self.assertTrue((self.install / "existing").exists())

    def test_missing_generator_preserves_previous_install(self):
        del self.entries["bin/grpc_cpp_plugin"]
        self.write_package()
        with self.assertRaisesRegex(RuntimeError, "missing required"):
            self.install_package()
        self.assertTrue((self.install / "existing").exists())


class GrpcSetupTests(unittest.TestCase):
    def test_cleanup_removes_a_writable_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary) / "source"
            checkout.mkdir()
            (checkout / "file").write_bytes(b"fixture")
            setup_grpc.remove_directory(checkout)
            self.assertFalse(checkout.exists())

    def test_windows_dependencies_select_the_static_runtime(self):
        arguments = setup_grpc.configure_arguments(
            "windows", "x86_64", Path("source"), Path("build"), Path("install")
        )
        for dependency in ("gRPC", "CARES", "protobuf", "ABSL"):
            with self.subTest(dependency=dependency):
                self.assertIn(f"-D{dependency}_MSVC_STATIC_RUNTIME=ON", arguments)

    def test_macos_builds_for_the_host_architecture_only(self):
        with patch.object(
            setup_grpc.platform, "system", return_value="Darwin"
        ), patch.object(setup_grpc.platform, "machine", return_value="arm64"):
            self.assertEqual(setup_grpc.host(), ("macos", "arm64"))
        arguments = setup_grpc.configure_arguments(
            "macos", "arm64", Path("source"), Path("build"), Path("install")
        )
        self.assertIn("-DCMAKE_OSX_ARCHITECTURES=arm64", arguments)
        self.assertFalse(any("MSVC" in str(argument) for argument in arguments))

    def test_cache_key_follows_the_pins_and_the_platform_build_options(self):
        grpc = {"tag": "v1.80.0", "commit": "f5e2d6e"}
        protobuf = {"version": "31.1"}
        linux = setup_grpc.cache_key(grpc, protobuf, "linux", "x86_64")
        self.assertEqual(linux, setup_grpc.cache_key(grpc, protobuf, "linux", "x86_64"))
        self.assertNotEqual(
            linux, setup_grpc.cache_key(grpc, protobuf, "windows", "x86_64")
        )
        self.assertNotEqual(
            linux,
            setup_grpc.cache_key(
                {**grpc, "commit": "0000000"}, protobuf, "linux", "x86_64"
            ),
        )
        configure_arguments = setup_grpc.configure_arguments
        with patch.object(
            setup_grpc,
            "configure_arguments",
            side_effect=lambda *arguments: configure_arguments(*arguments)
            + ["-DEXTRA=ON"],
        ):
            self.assertNotEqual(
                linux, setup_grpc.cache_key(grpc, protobuf, "linux", "x86_64")
            )

    @unittest.skipUnless(os.name == "nt", "Windows read-only file semantics")
    def test_retry_removes_read_only_git_pack_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            checkout = Path(temporary) / "source"
            pack = checkout / ".git/modules/abseil/objects/pack/pack.idx"
            pack.parent.mkdir(parents=True)
            pack.write_bytes(b"pack index fixture")
            pack.chmod(stat.S_IREAD)
            setup_grpc.remove_directory(checkout)
            self.assertFalse(checkout.exists())

    def test_cleanup_does_not_hide_other_permission_errors(self):
        with tempfile.TemporaryDirectory() as temporary:
            writable = Path(temporary) / "locked.idx"
            writable.write_bytes(b"fixture")
            failure = PermissionError("file is locked")

            def fail_removal(path, onerror):
                onerror(os.unlink, str(writable), (PermissionError, failure, None))

            with patch.object(setup_grpc.shutil, "rmtree", side_effect=fail_removal):
                with self.assertRaises(PermissionError) as caught:
                    setup_grpc.remove_directory(Path(temporary))
            self.assertIs(caught.exception, failure)


if __name__ == "__main__":
    unittest.main()
