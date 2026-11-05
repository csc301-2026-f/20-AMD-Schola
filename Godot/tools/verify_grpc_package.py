#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

"""Generate, link, and run a small client against the installed gRPC package."""

import os
import subprocess
import tempfile
from pathlib import Path

import setup_grpc


def main():
    system, _ = setup_grpc.host()
    root = setup_grpc.INSTALL_DIRECTORY.resolve()
    suffix = ".exe" if system == "windows" else ""
    with tempfile.TemporaryDirectory(prefix="grpc-smoke-") as temporary:
        directory = Path(temporary)
        schema = directory / "smoke.proto"
        schema.write_text(
            'syntax = "proto3";\npackage vendor_test;\n'
            "message Message { string text = 1; }\n"
            "service Echo { rpc Send(Message) returns (Message); }\n",
            encoding="utf-8",
        )
        setup_grpc.run(
            [
                root / "bin" / f"protoc{suffix}",
                f"--proto_path={directory}",
                f"--cpp_out={directory}",
                f"--grpc_out={directory}",
                f"--plugin=protoc-gen-grpc={root / 'bin' / f'grpc_cpp_plugin{suffix}'}",
                schema,
            ]
        )
        source = directory / "main.cpp"
        source.write_text(
            '#include "smoke.grpc.pb.h"\n#include <grpcpp/grpcpp.h>\n'
            "int main() {\n"
            '  vendor_test::Message input, output; input.set_text("verified");\n'
            '  if (!output.ParseFromString(input.SerializeAsString()) || output.text() != "verified") return 1;\n'
            '  auto stub = vendor_test::Echo::NewStub(grpc::CreateChannel("localhost:1", grpc::InsecureChannelCredentials()));\n'
            "  return stub ? 0 : 2;\n}\n",
            encoding="utf-8",
        )
        executable = directory / f"smoke{suffix}"
        sources = [source, directory / "smoke.pb.cc", directory / "smoke.grpc.pb.cc"]
        if system == "windows":
            arguments = [
                "/nologo",
                "/std:c++17",
                "/EHsc",
                "/MT",
                f"/I{root / 'include'}",
                f"/I{directory}",
                f"/Fe:{executable}",
            ]
            arguments += [str(path) for path in sources]
            arguments += ["/link"] + [
                str(path) for path in sorted((root / "lib").glob("*.lib"))
            ]
            arguments += [
                f"{name}.lib"
                for name in (
                    "ws2_32",
                    "crypt32",
                    "iphlpapi",
                    "advapi32",
                    "bcrypt",
                    "dbghelp",
                )
            ]
            response = directory / "compile.rsp"
            response.write_text(subprocess.list2cmdline(arguments), encoding="utf-8")
            setup_grpc.run(["cl", f"@{response}"], directory)
        elif system == "linux":
            setup_grpc.run(
                [
                    os.environ.get("CXX", "c++"),
                    "-std=c++17",
                    f"-I{root / 'include'}",
                    f"-I{directory}",
                    *sources,
                    "-o",
                    executable,
                    "-Wl,--start-group",
                    *sorted((root / "lib").glob("*.a")),
                    "-Wl,--end-group",
                    "-pthread",
                    "-ldl",
                    "-lm",
                    "-lrt",
                ],
                directory,
            )
        else:
            raise RuntimeError(f"No committed-package smoke test for {system}")
        setup_grpc.run([executable], directory)
    print("gRPC/protobuf generators, static libraries, and runtime smoke check passed.")


if __name__ == "__main__":
    main()
