# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import io
import json
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import setup_onnxruntime as setup


class OfflineInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.vendor = self.root / "vendor"
        self.vendor.mkdir()
        self.install = self.root / "installed"
        self.install.mkdir()
        (self.install / "keep").write_text("existing install")
        self.lock = self.root / "lock.json"
        self.lock.write_text(
            json.dumps(
                {"onnxruntime": {"version": "1.30.0", "archives": {"linux-x86_64": {}}}}
            )
        )
        for name, value in (
            ("GODOT_ROOT", self.root),
            ("LOCK_FILE", self.lock),
            ("INSTALL_DIRECTORY", self.install),
            ("VENDOR_DIRECTORY", self.vendor),
        ):
            context = patch.object(setup, name, value)
            context.start()
            self.addCleanup(context.stop)
        context = patch.object(setup, "host_platform", return_value="linux-x86_64")
        context.start()
        self.addCleanup(context.stop)

    def package(self, version="1.30.0", unsafe=False):
        archive = self.vendor / "linux-x86_64.tar.gz"
        files = {
            "include/onnxruntime_c_api.h": "header",
            "VERSION_NUMBER": version,
            "lib/libonnxruntime.so": "runtime",
            "lib/libonnxruntime.so.1": "runtime",
            "LICENSE": "license",
            "ThirdPartyNotices.txt": "notices",
        }
        if unsafe:
            files["../../outside"] = "bad"
        with tarfile.open(archive, "w:gz") as output:
            for name, value in files.items():
                data = value.encode()
                entry = tarfile.TarInfo("onnxruntime/" + name)
                entry.size = len(data)
                output.addfile(entry, io.BytesIO(data))
        self.manifest = {
            "file": archive.name,
            "host": "linux-x86_64",
            "version": "1.30.0",
            "sha256": setup.sha256(archive),
        }
        self.write_manifest()
        return archive

    def write_manifest(self):
        (self.vendor / "linux-x86_64.json").write_text(json.dumps(self.manifest))

    def test_installs_without_network_when_upstream_is_unavailable(self):
        self.package()
        with patch(
            "urllib.request.urlopen", side_effect=AssertionError("network forbidden")
        ):
            setup.main()
        self.assertEqual(
            (self.install / "lib/libonnxruntime.so.1").read_text(), "runtime"
        )
        self.assertFalse((self.install / "keep").exists())

    def test_corrupt_archive_preserves_existing_install(self):
        self.package().write_bytes(b"corrupt")
        with self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
            setup.main()
        self.assertTrue((self.install / "keep").is_file())

    def test_lfs_pointer_explains_how_to_fetch_package(self):
        self.package().write_text("version https://git-lfs.github.com/spec/v1\n")
        with self.assertRaisesRegex(RuntimeError, "git lfs pull"):
            setup.main()

    def test_archive_version_mismatch_preserves_existing_install(self):
        self.package(version="1.29.0")
        with self.assertRaisesRegex(RuntimeError, "version does not match"):
            setup.main()
        self.assertTrue((self.install / "keep").is_file())

    def test_path_traversal_is_rejected(self):
        self.package(unsafe=True)
        with self.assertRaises(tarfile.FilterError):
            setup.main()
        self.assertFalse((self.root / "outside").exists())
        self.assertTrue((self.install / "keep").is_file())

    def test_manifest_filename_cannot_escape_vendor_directory(self):
        self.package()
        self.manifest["file"] = "../other.tar.gz"
        self.write_manifest()
        with self.assertRaisesRegex(RuntimeError, "Unexpected.*filename"):
            setup.main()


if __name__ == "__main__":
    unittest.main()
