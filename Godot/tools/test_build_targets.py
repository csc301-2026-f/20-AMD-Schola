# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class BuildTargetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copy(Path(__file__).resolve().parents[1] / "SConstruct", self.root)
        # Replace only the external godot-cpp build; exercise the real Schola graph.
        self.write(
            "godot-cpp/SConstruct",
            "Import('env')\n"
            "env.Replace(tools=[], platform='linux', arch='x86_64', "
            "suffix='.linux.template_debug.x86_64')\n"
            "env.Tool('gcc'); env.Tool('g++'); env.Tool('gnulink'); env.Tool('ar')\n"
            "env.Replace(PROGSUFFIX='', SHLIBPREFIX='lib', SHLIBSUFFIX='.so')\n"
            "Return('env')\n",
        )
        self.write("src/core/stub.cpp", "int stub() { return 0; }\n")
        self.write("catch2/extras/catch_amalgamated.cpp", "int main() { return 0; }\n")
        self.write("thirdparty/onnxruntime/include/onnxruntime_c_api.h", "")
        self.write("thirdparty/onnxruntime/lib/libonnxruntime.so.1", "")

    def write(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def run_scons(self, *targets):
        return subprocess.run(
            [sys.executable, "-m", "SCons", "-n", *targets],
            cwd=self.root,
            capture_output=True,
            text=True,
        )

    def test_non_transport_targets_do_not_require_grpc(self):
        for target in (
            "unit_tests",
            "inference_tests",
            "schola",
            "build/tests/schola_core_tests",
            "build/tests/schola_inference_tests",
            "build/linux/libschola.linux.template_debug.x86_64.so",
            "addons/schola/bin/linux/libschola.linux.template_debug.x86_64.so",
        ):
            with self.subTest(target=target):
                result = self.run_scons(target)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("protoc", result.stdout)

    def test_training_targets_still_require_grpc(self):
        for targets in (
            (),
            ("schola_training",),
            ("transport_tests",),
            ("unit_tests", "transport_tests"),
            ("build/linux/libschola_training.linux.template_debug.x86_64.so",),
        ):
            with self.subTest(targets=targets):
                result = self.run_scons(*targets)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("gRPC is missing", result.stdout)


if __name__ == "__main__":
    unittest.main()
