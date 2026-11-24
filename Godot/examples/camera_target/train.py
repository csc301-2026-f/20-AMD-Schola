# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
"""Train the camera target example over Schola's gRPC connector and export ONNX."""

import argparse
import subprocess
from pathlib import Path

import numpy as np
import torch
from schola.core.protocols.protobuf.grpc_protocol import GrpcProtocol
from schola.core.simulators.external_simulator import ExternalSimulator
from schola.sb3.env import VecEnv
from schola.sb3.export import save_model_as_onnx
from schola.sb3.utils import VecMergeDictActionWrapper
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback
from stable_baselines3.common.vec_env import VecMonitor

CAMERA = "00000000:Camera"


def smoke(env):
    observation = env.reset()
    assert observation[CAMERA].shape == (1, 3, 64, 64), observation[CAMERA].shape
    endings = 0
    saw_ball = False
    lost_ball = False
    for _ in range(300):
        observation, reward, done, _ = env.step(np.array([[10.0]], dtype=np.float32))
        image = observation[CAMERA][0]
        assert np.isfinite(reward).all()
        assert np.isfinite(image).all() and image.min() >= 0.0 and image.max() <= 1.0
        assert (
            image.mean() > 0.05
        ), "The camera image is black; keep the Godot window visible"
        red = int(((image[0] > 0.8) & (image[1] < 0.2)).sum())
        saw_ball = saw_ball or red > 0
        lost_ball = lost_ball or red == 0
        endings += int(done.sum())
    assert saw_ball and lost_ball, "Turning did not change what the camera sees"
    assert endings > 0, "No episode ended"
    print(f"CAMERA_SMOKE_OK: 300 steps, {endings} episode endings", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot executable path")
    parser.add_argument("--steps", type=int, default=100_000)
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--smoke", action="store_true", help="Check the camera pipeline before training"
    )
    args = parser.parse_args()
    if args.steps <= 0:
        parser.error("--steps must be positive")
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    torch.set_num_threads(2)
    example = Path(__file__).resolve().parent
    output = example / "policies"
    output.mkdir(exist_ok=True)
    process = subprocess.Popen(
        [
            args.godot,
            "--path",
            str(example.parents[1]),
            "--fixed-fps",
            "60",
            "res://examples/camera_target/scenes/camera_target_train.tscn",
            "--",
            f"--ScholaPort={args.port}",
        ]
    )
    env = None
    try:
        env = VecMergeDictActionWrapper(
            VecEnv(ExternalSimulator(), GrpcProtocol("127.0.0.1", args.port))
        )
        if args.smoke:
            smoke(env)
        model = PPO(
            "MultiInputPolicy",
            VecMonitor(env),
            n_steps=512,
            batch_size=64,
            seed=7,
            device="cpu",
            verbose=1,
            policy_kwargs={"features_extractor_kwargs": {"normalized_image": True}},
        )
        model.learn(
            total_timesteps=args.steps,
            callback=CheckpointCallback(
                save_freq=25000, save_path=str(output), name_prefix="camera_target"
            ),
        )
        model.save(output / "camera_target")
        save_model_as_onnx(
            model,
            str(output / "camera_target.onnx"),
            action_space=env.unmerged_action_space,
        )
        print(
            f"Training and export complete: {output / 'camera_target.onnx'}", flush=True
        )
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
