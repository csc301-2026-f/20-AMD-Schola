# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import setup_grpc


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
