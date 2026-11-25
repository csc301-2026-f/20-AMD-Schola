# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
import argparse
import math
from pathlib import Path
import subprocess

import numpy as np
import torch
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.vec_env import VecMonitor
from schola.core.protocols.protobuf.async_grpc_protocol import AsyncGrpcProtocol
from schola.core.protocols.protobuf.grpc_protocol import GrpcProtocol
from schola.core.simulators.external_simulator import ExternalSimulator
from schola.sb3.async_env import AsyncVecEnv
from schola.sb3.env import VecEnv
from schola.sb3.export import save_model_as_onnx
from schola.sb3.utils import VecMergeDictActionWrapper

SCENE = "res://examples/race_track/scenes/race_track_train.tscn"
CHECK_STEPS = 100_000
TEST_DRIVE_LAYOUTS = 5
PPO_SETTINGS = dict(
    n_steps=1024, batch_size=128, gamma=0.99, gae_lambda=0.98, learning_rate=1e-4
)


def launch(godot, port, *flags):
    return subprocess.Popen([*godot, SCENE, "--", f"--ScholaPort={port}", *flags])


def connect(port):
    return VecMergeDictActionWrapper(
        VecEnv(ExternalSimulator(), GrpcProtocol("127.0.0.1", port))
    )


def connect_all(ports):
    if len(ports) == 1:
        return connect(ports[0])
    return VecMergeDictActionWrapper(
        AsyncVecEnv(
            [ExternalSimulator() for _ in ports],
            [AsyncGrpcProtocol("127.0.0.1", port) for port in ports],
        )
    )


def stop(process, env):
    try:
        if env is not None:
            env.close()
    finally:
        for running in process if isinstance(process, list) else [process]:
            if running is not None:
                running.terminate()
                try:
                    running.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    running.kill()
                    running.wait()


def test_drive(model, godot, port):
    process = launch(godot, port, "--race-track-start-line")
    env = None
    try:
        env = connect(port)
        obs = env.reset()
        score = 0.0
        metres = 0.0
        drifting = 0
        for _ in range(TEST_DRIVE_LAYOUTS):
            done = [False]
            while not done[0]:
                action, _ = model.predict(obs, deterministic=True)
                obs, reward, done, infos = env.step(action)
                score += float(reward[0])
                metres += float(infos[0]["progress"])
                drifting += float(infos[0]["drift"]) > 0.5
        score /= TEST_DRIVE_LAYOUTS
        print(
            f"Test drive on {TEST_DRIVE_LAYOUTS} layouts: average score {score:.1f}, "
            f"{metres / TEST_DRIVE_LAYOUTS:.1f} m, drifting {drifting / 60 / TEST_DRIVE_LAYOUTS:.1f} s",
            flush=True,
        )
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
        self.next_check = None

    def _on_step(self):
        if self.next_check is None:
            self.next_check = self.model.num_timesteps + CHECK_STEPS
        if self.model.num_timesteps >= self.next_check:
            self.next_check += CHECK_STEPS
            self.check()
        return True

    def save(self, name):
        self.model.save(self.output / name)
        save_model_as_onnx(
            self.model,
            str(self.output / f"{name}.onnx"),
            action_space=self.action_space,
        )

    def check(self):
        self.save("race_track_latest")
        (self.output / "checkpoints").mkdir(exist_ok=True)
        save_model_as_onnx(
            self.model,
            str(
                self.output
                / "checkpoints"
                / f"race_track_{self.model.num_timesteps}.onnx"
            ),
            action_space=self.action_space,
        )
        score = test_drive(self.model, self.godot, self.port)
        steps = self.model.num_timesteps
        if score <= self.best:
            print(
                f"Test drive after {steps} steps: score {score:.1f}, best is still {self.best:.1f}",
                flush=True,
            )
            return
        self.best = score
        self.save("race_track")
        print(
            f"Test drive after {steps} steps: score {score:.1f}, new best saved",
            flush=True,
        )


def main():
    parser = argparse.ArgumentParser(
        description="Train the race track with Schola's native gRPC connector and save the best policy as ONNX."
    )
    parser.add_argument("--godot", default="godot", help="Godot executable path")
    parser.add_argument("--steps", type=int, default=100_000)
    parser.add_argument(
        "--resume",
        nargs="?",
        const="best",
        choices=["best", "latest"],
        help="Continue training the saved best model, or the latest one with --resume latest",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="First training port; each extra Godot uses the next port, and test drives use the port after them",
    )
    parser.add_argument(
        "--envs",
        type=int,
        default=1,
        help="Number of Godot processes training in parallel",
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
    parser.add_argument(
        "--seed",
        type=int,
        default=7,
        help="Random seed for a new policy and the training layouts",
    )
    args = parser.parse_args()
    if args.steps <= 0:
        parser.error("--steps must be positive")
    if args.envs < 1 or (args.attach and args.envs != 1):
        parser.error("--envs must be at least 1, and 1 with --attach")
    if not 1 <= args.port <= 65535 - args.envs:
        parser.error("--port leaves no room for the test-drive port")
    ports = [args.port + index for index in range(args.envs)]
    test_port = args.port + args.envs
    torch.set_num_threads(2)
    example = Path(__file__).resolve().parent
    project = example.parents[1]
    output = example / "policies"
    output.mkdir(exist_ok=True)
    godot = [args.godot, "--path", str(project), "--fixed-fps", "60"]
    if args.headless:
        godot.append("--headless")
    process = None if args.attach else [launch(godot, port) for port in ports]
    env = None
    try:
        env = connect_all(ports)
        print(
            "Observation:",
            env.observation_space,
            "\nAction:",
            env.action_space,
            flush=True,
        )
        if args.smoke:
            obs = env.reset()
            assert [value.shape[1:] for value in obs.values()] == [
                (6,),
                (3,),
                (75,),
                (3,),
            ], obs
            peak_speed = 0.0
            episodes = 0
            for _ in range(600):
                obs, reward, done, info = env.step(
                    np.array([[0.0, 1.0]] * env.num_envs, dtype=np.float32)
                )
                assert np.isfinite(reward).all()
                assert all(np.isfinite(value).all() for value in obs.values())
                peak_speed = max(
                    peak_speed,
                    float(np.linalg.norm(list(obs.values())[1], axis=1).max()) * 2,
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
            saved = (
                "race_track_latest.zip" if args.resume == "latest" else "race_track.zip"
            )
            model = PPO.load(
                output / saved,
                env=monitored_env,
                device="cpu",
                verbose=1,
                **PPO_SETTINGS,
            )
            best = test_drive(model, godot, test_port)
            print(f"Saved model test drive: score {best:.1f}", flush=True)
        else:
            model = PPO(
                "MultiInputPolicy",
                monitored_env,
                **PPO_SETTINGS,
                seed=args.seed,
                device="cpu",
                verbose=1,
            )
        keep_best = KeepBest(godot, test_port, output, env.unmerged_action_space, best)
        model.learn(
            total_timesteps=args.steps,
            reset_num_timesteps=not args.resume,
            callback=keep_best,
        )
        keep_best.check()
        print(
            f'Training complete, best test drive score {keep_best.best:.1f}: {output / "race_track.onnx"}',
            flush=True,
        )
    finally:
        stop(process, env)


if __name__ == "__main__":
    main()
