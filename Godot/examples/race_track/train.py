# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
"""Train the race track with Schola's native gRPC connector and export ONNX."""

import argparse
from pathlib import Path
import subprocess

import numpy as np
import torch
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import VecMonitor
from stable_baselines3.common.callbacks import CheckpointCallback
from schola.core.protocols.protobuf.grpc_protocol import GrpcProtocol
from schola.core.simulators.external_simulator import ExternalSimulator
from schola.sb3.env import VecEnv
from schola.sb3.export import save_model_as_onnx
from schola.sb3.utils import VecMergeDictActionWrapper


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot executable path")
    parser.add_argument("--steps", type=int, default=100_000)
    parser.add_argument(
        "--resume", action="store_true", help="Continue the saved PPO checkpoint"
    )
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--headless", action="store_true")
    parser.add_argument(
        "--smoke",
        action="store_true",
        help="Check motion and autoreset before training",
    )
    args = parser.parse_args()
    if args.steps <= 0:
        parser.error("--steps must be positive")
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    torch.set_num_threads(2)
    example = Path(__file__).resolve().parent
    project = example.parents[1]
    output = example / "policies"
    output.mkdir(exist_ok=True)
    command = [args.godot, "--path", str(project), "--fixed-fps", "60"]
    if args.headless:
        command.append("--headless")
    command += [
        "res://examples/race_track/scenes/race_track_train.tscn",
        "--",
        f"--ScholaPort={args.port}",
    ]
    process = subprocess.Popen(command)
    env = None
    try:
        env = VecMergeDictActionWrapper(
            VecEnv(ExternalSimulator(), GrpcProtocol("127.0.0.1", args.port))
        )
        print(
            "Observation:",
            env.observation_space,
            "\nAction:",
            env.action_space,
            flush=True,
        )
        if args.smoke:
            obs = env.reset()
            assert [value.shape for value in obs.values()] == [(1, 6), (1, 3)], obs
            peak_speed = 0.0
            episodes = 0
            for _ in range(600):
                obs, reward, done, info = env.step(
                    np.array([[0.0, 1.0]], dtype=np.float32)
                )
                assert np.isfinite(reward).all()
                assert all(np.isfinite(value).all() for value in obs.values())
                peak_speed = max(
                    peak_speed, float(np.linalg.norm(list(obs.values())[1])) * 2
                )
                episodes += int(done.sum())
            assert peak_speed > 1.0, f"No vehicle motion: {peak_speed}"
            assert episodes > 0, "No episode completion/autoreset"
            print(
                f"GRPC_SMOKE_OK: 600 steps, peak {peak_speed:.2f} m/s, {episodes} episode endings",
                flush=True,
            )
        monitored_env = VecMonitor(env)
        if args.resume:
            model = PPO.load(output / "race_track.zip", env=monitored_env, device="cpu")
        else:
            model = PPO(
                "MultiInputPolicy",
                monitored_env,
                n_steps=512,
                batch_size=64,
                seed=7,
                device="cpu",
                verbose=1,
            )
        model.learn(
            total_timesteps=args.steps,
            reset_num_timesteps=not args.resume,
            callback=CheckpointCallback(
                save_freq=25000, save_path=str(output), name_prefix="race_track"
            ),
        )
        model.save(output / "race_track")
        save_model_as_onnx(
            model,
            str(output / "race_track.onnx"),
            action_space=env.unmerged_action_space,
        )
        print(f'Training and export complete: {output / "race_track.onnx"}', flush=True)
    finally:
        try:
            if env is not None:
                env.close()
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
