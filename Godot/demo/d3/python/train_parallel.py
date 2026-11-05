#!/usr/bin/env python3
"""Classic synchronous parallel training for the Schola D3 demo.

Starts N Godot instances of the D3 scene, each on its own port and its own CPU core, then runs
trainer.py against all of them. The trainer steps every instance in lockstep, resets each one when
its episode ends, and learns one shared Q-table, which it saves and exports to ONNX. The instances
quit when training ends.

    python train_parallel.py --godot <path/to/godot> --instances 4 --episodes 1200
    python train_parallel.py --godot <path/to/godot> --instances 4 --windowed
"""

from __future__ import annotations

import argparse
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
WINDOW_SIZE = (640, 400)


def port_is_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        try:
            probe.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


def godot_command(args: argparse.Namespace, index: int, port: int) -> list[str]:
    command = [args.godot, "--path", str(PROJECT)]
    if args.windowed:
        columns = 2 if args.instances > 1 else 1
        x = 40 + (index % columns) * (WINDOW_SIZE[0] + 10)
        y = 40 + (index // columns) * (WINDOW_SIZE[1] + 40)
        command += ["--resolution", f"{WINDOW_SIZE[0]}x{WINDOW_SIZE[1]}", "--position", f"{x},{y}"]
    else:
        command.append("--headless")
    command += ["--", f"--port={port}", f"--speed={args.speed}", "--train", "--quit-after-training"]
    if args.viewer_port:
        command.append(f"--viewer={args.viewer_port}")
    return command


def stop_all(processes: list[subprocess.Popen], timeout: float) -> None:
    deadline = time.monotonic() + timeout
    for process in processes:
        remaining = max(0.0, deadline - time.monotonic())
        try:
            process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"), help="Godot 4.7 executable (or set GODOT)")
    parser.add_argument("--instances", type=int, default=4)
    parser.add_argument("--base-port", type=int, default=8000)
    parser.add_argument("--episodes", type=int, default=1200, help="Total episodes across all instances")
    parser.add_argument("--speed", type=int, default=0, help="Steps per second per instance (default: 2000 headless, 60 windowed)")
    parser.add_argument("--windowed", action="store_true", help="Show each instance in its own window instead of headless")
    parser.add_argument("--log-dir", type=Path, default=HERE / "logs")
    parser.add_argument("--log-file", type=Path, help="Write the launcher's and trainer's output here instead of the console")
    parser.add_argument("--viewer-port", type=int, default=0, help="UDP port of a Schola D3 parallel viewer to report to")
    parser.add_argument("--policy-out", type=Path, default=PROJECT / "policies" / "q_policy.json")
    parser.add_argument("--onnx-out", type=Path, default=PROJECT / "policies" / "q_policy.onnx")
    args = parser.parse_args()
    if args.instances < 1:
        parser.error("--instances must be at least 1")
    if args.speed <= 0:
        args.speed = 60 if args.windowed else 2000
    output = None
    if args.log_file is not None:
        args.log_file.parent.mkdir(parents=True, exist_ok=True)
        output = open(args.log_file, "w", encoding="utf-8", buffering=1)
        sys.stdout = sys.stderr = output

    ports = list(range(args.base_port, args.base_port + args.instances))
    busy = [port for port in ports if not port_is_free(port)]
    if busy:
        print(f"error: ports {busy} are in use; close the program using them or pass another --base-port", file=sys.stderr)
        return 1

    args.log_dir.mkdir(parents=True, exist_ok=True)
    processes: list[subprocess.Popen] = []
    logs = []
    try:
        for index, port in enumerate(ports):
            log = open(args.log_dir / f"godot_{port}.log", "w", encoding="utf-8")
            logs.append(log)
            try:
                processes.append(subprocess.Popen(godot_command(args, index, port), stdout=log, stderr=subprocess.STDOUT))
            except OSError as error:
                print(f"error: could not start Godot '{args.godot}': {error}", file=sys.stderr)
                return 1
        print(f"started {args.instances} Godot instance(s) on ports {ports}; logs in {args.log_dir}", flush=True)

        trainer = [
            sys.executable, str(HERE / "trainer.py"),
            "--port", *[str(port) for port in ports],
            "--episodes", str(args.episodes),
            "--policy-out", str(args.policy_out),
            "--onnx-out", str(args.onnx_out),
        ]
        result = subprocess.run(trainer, stdout=output, stderr=subprocess.STDOUT if output else None)
        stop_all(processes, timeout=15.0)
        failed = [port for port, process in zip(ports, processes) if process.returncode != 0]
        if failed:
            print(f"Godot instances on ports {failed} exited with an error; see their logs in {args.log_dir}", file=sys.stderr)
        return result.returncode or (1 if failed else 0)
    except KeyboardInterrupt:
        print("interrupted; stopping Godot instances", file=sys.stderr)
        for process in processes:
            process.kill()
        return 130
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
        for log in logs:
            log.close()
        if output is not None:
            sys.stdout, sys.stderr = sys.__stdout__, sys.__stderr__
            output.close()


if __name__ == "__main__":
    sys.exit(main())
