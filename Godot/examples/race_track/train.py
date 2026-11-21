# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
"""Train the race track with Schola's native gRPC connector and save the best policy as ONNX."""

import argparse
import math
from pathlib import Path
import subprocess

import numpy as np
import torch
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.evaluation import evaluate_policy
from stable_baselines3.common.vec_env import VecMonitor
from schola.core.protocols.protobuf.grpc_protocol import GrpcProtocol
from schola.core.simulators.external_simulator import ExternalSimulator
from schola.sb3.env import VecEnv
from schola.sb3.export import save_model_as_onnx
from schola.sb3.utils import VecMergeDictActionWrapper

SCENE = "res://examples/race_track/scenes/race_track_train.tscn"
TEST_DRIVE_STEPS = 25_000


def launch(godot, port):
    return subprocess.Popen([*godot, SCENE, "--", f"--ScholaPort={port}"])


def connect(port):
    return VecMergeDictActionWrapper(
        VecEnv(ExternalSimulator(), GrpcProtocol("127.0.0.1", port))
    )


def stop(process, env):
    try:
        if env is not None:
            env.close()
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def test_drive(model, godot, port):
    process = launch(godot, port)
    env = None
    try:
        env = VecMonitor(connect(port))
        score, _ = evaluate_policy(model, env, n_eval_episodes=1)
        return score
    finally:
        stop(process, env)


class KeepBest(BaseCallback):
    def __init__(self, godot, port, output, action_space, best):
        super().__init__()
        self.godot = godot
        self.port = port
        self.output = output
        self.action_space = action_space
        self.best = best

    def _on_step(self):
        if self.n_calls % TEST_DRIVE_STEPS == 0:
            self.check()
        return True

    def check(self):
        score = test_drive(self.model, self.godot, self.port)
        steps = self.model.num_timesteps
        if score <= self.best:
            print(
                f"Test drive after {steps} steps: {score:.1f}, best is still {self.best:.1f}",
                flush=True,
            )
            return
        self.best = score
        self.model.save(self.output / "race_track")
        save_model_as_onnx(
            self.model,
            str(self.output / "race_track.onnx"),
            action_space=self.action_space,
        )
        print(
            f"Test drive after {steps} steps: {score:.1f}, new best saved", flush=True
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot executable path")
    parser.add_argument("--steps", type=int, default=100_000)
    parser.add_argument(
        "--resume", action="store_true", help="Continue training the saved best model"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="Training port; test drives use the next port",
    )
    parser.add_argument("--headless", action="store_true")
    parser.add_argument(
        "--attach",
        action="store_true",
        help="Train a scene already running in Godot instead of launching one",
    )
    parser.add_argument(
        "--smoke",
        action="store_true",
        help="Check motion and autoreset before training",
    )
    args = parser.parse_args()
    if args.steps <= 0:
        parser.error("--steps must be positive")
    if not 1 <= args.port <= 65534:
        parser.error("--port must be between 1 and 65534")
    torch.set_num_threads(2)
    example = Path(__file__).resolve().parent
    project = example.parents[1]
    output = example / "policies"
    output.mkdir(exist_ok=True)
    godot = [args.godot, "--path", str(project), "--fixed-fps", "60"]
    if args.headless:
        godot.append("--headless")
    process = None if args.attach else launch(godot, args.port)
    env = None
    try:
        env = connect(args.port)
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
        best = -math.inf
        if args.resume:
            model = PPO.load(output / "race_track.zip", env=monitored_env, device="cpu")
            best = test_drive(model, godot, args.port + 1)
            print(f"Saved model test drive: {best:.1f}", flush=True)
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
        keep_best = KeepBest(
            godot, args.port + 1, output, env.unmerged_action_space, best
        )
        model.learn(
            total_timesteps=args.steps,
            reset_num_timesteps=not args.resume,
            callback=keep_best,
        )
        keep_best.check()
        print(
            f'Training complete, best test drive {keep_best.best:.1f}: {output / "race_track.onnx"}',
            flush=True,
        )
    finally:
        stop(process, env)


if __name__ == "__main__":
    main()
