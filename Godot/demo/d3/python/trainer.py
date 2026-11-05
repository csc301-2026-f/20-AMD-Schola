# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

"""Tabular Q-learning client for the Schola D3 demo, over one or more Godot instances.

Talks to Godot's ScholaLocalConnector (the stand-in for US3) with newline-delimited JSON over
localhost TCP. As in Schola's GymService, Python sends every request and Godot answers it:
start, definition, then update (reset, step, close). See Godot/docs/local_protocol.md.

With several ports, the trainer runs classic synchronous parallel training: every round it sends
one action to each Godot instance at once, waits for all of them, and updates one shared Q-table.
An instance whose episode ends is reset in the same round, so no instance sits idle.

    python trainer.py --port 8000 --episodes 300
    python trainer.py --port 8000 8001 8002 8003 --episodes 1200
"""

from __future__ import annotations

import argparse
import json
import math
import random
import socket
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import gymnasium as gym
import numpy as np

POLICY_FORMAT = "schola-d3-qtable"
PROGRESS_INTERVAL_SEC = 0.25


class StopRequested(Exception):
    pass


def space_from_dict(definition: dict) -> gym.Space:
    # Unbounded Box sides arrive as null.
    kind = definition["type"]
    if kind == "Box":
        low = np.array([-np.inf if v is None else v for v in definition["low"]], dtype=np.float32)
        high = np.array([np.inf if v is None else v for v in definition["high"]], dtype=np.float32)
        shape = tuple(int(d) for d in definition["shape"])
        return gym.spaces.Box(low.reshape(shape), high.reshape(shape), shape, dtype=np.dtype(definition["dtype"]))
    if kind == "Discrete":
        return gym.spaces.Discrete(int(definition["n"]))
    if kind == "MultiDiscrete":
        return gym.spaces.MultiDiscrete([int(n) for n in definition["nvec"]])
    if kind == "MultiBinary":
        return gym.spaces.MultiBinary(int(definition["n"]))
    if kind == "Dict":
        return gym.spaces.Dict({key: space_from_dict(value) for key, value in definition["spaces"].items()})
    raise ValueError(f"unknown space type {kind!r}")


class GodotConnection:
    def __init__(self, host: str, port: int, timeout: float) -> None:
        self.port = port
        deadline = time.monotonic() + timeout
        while True:
            try:
                self.sock = socket.create_connection((host, port), timeout=2.0)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise ConnectionError(f"could not connect to Godot at {host}:{port}; is it running and listening?")
                time.sleep(0.25)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.sock.settimeout(None)
        self.reader = self.sock.makefile("r", encoding="utf-8")

    def notify(self, message: dict) -> None:
        """Sends a one-way demo message (progress, saved, log); Godot does not reply."""
        try:
            self.sock.sendall((json.dumps(message) + "\n").encode("utf-8"))
        except OSError:
            pass

    def request(self, message: dict, expected: str) -> dict:
        """Sends one request and returns Godot's reply, which must have type ``expected``."""
        self.sock.sendall((json.dumps(message) + "\n").encode("utf-8"))
        line = self.reader.readline()
        if not line:
            raise ConnectionError(f"Godot on port {self.port} closed the connection")
        reply = json.loads(line)
        if reply.get("type") == "error":
            if reply.get("code") == "CLOSED":
                raise StopRequested(f"port {self.port}: {reply.get('message', '')}")
            raise RuntimeError(f"Godot on port {self.port} rejected {message['type']} ({reply.get('code')}): {reply.get('message')}")
        if reply.get("type") != expected:
            raise RuntimeError(f"expected {expected} from Godot on port {self.port}, got {reply}")
        return reply

    def close_session(self) -> None:
        """Ends the session cleanly; safe to call after Godot has already closed."""
        try:
            self.request({"type": "update", "status": "CLOSED"}, "close_result")
        except (OSError, ConnectionError, RuntimeError, StopRequested, json.JSONDecodeError):
            pass

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass


class GodotGridEnv(gym.Env):
    """One Godot instance as a Gymnasium environment."""

    def __init__(self, connection: GodotConnection) -> None:
        self.connection = connection
        connection.request({"type": "start", "autoreset_mode": "DISABLED"}, "start_result")
        environments = connection.request({"type": "definition"}, "definition_result")["environments"]
        if len(environments) != 1 or len(environments[0]) != 1:
            raise RuntimeError(f"this trainer supports one environment with one agent per instance, got {environments}")
        (self.agent_id, self.definition), = environments[0].items()
        self.observation_space = space_from_dict(self.definition["observation_space"])
        self.action_space = space_from_dict(self.definition["action_space"])

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        super().reset(seed=seed)
        reply = self.connection.request(
            {"type": "update", "reset": {"environments": {"0": {"seed": seed, "options": options or {}}}}},
            "reset_result",
        )
        agent = reply["initial_state"]["0"][self.agent_id]
        return self._observation(agent), agent.get("info", {})

    def step(self, action):
        # The client validates actions before sending, as Schola's Python package does.
        if not self.action_space.contains(action):
            raise ValueError(f"action {action!r} is outside {self.action_space}")
        reply = self.connection.request(
            {"type": "update", "step": {"actions": [{self.agent_id: int(action)}]}},
            "step_result",
        )
        agent = reply["state"][0][self.agent_id]
        return (
            self._observation(agent),
            float(agent["reward"]),
            bool(agent["terminated"]),
            bool(agent["truncated"]),
            agent.get("info", {}),
        )

    def _observation(self, reply: dict) -> np.ndarray:
        observation = np.asarray(reply["observation"], dtype=self.observation_space.dtype)
        if not self.observation_space.contains(observation):
            raise RuntimeError(f"observation {observation} is outside {self.observation_space}")
        return observation


class GodotVectorEnv:
    """Steps several Godot instances in lockstep, one thread each, and resets finished ones.

    Each instance is a separate Godot process, so their simulations run on separate cores while
    the threads wait on their sockets.
    """

    def __init__(self, envs: list[GodotGridEnv], rng: random.Random) -> None:
        if not envs:
            raise ValueError("at least one Godot instance is required")
        self.envs = envs
        self.rng = rng
        self.num_envs = len(envs)
        self.observation_space = envs[0].observation_space
        self.action_space = envs[0].action_space
        for env in envs[1:]:
            if env.definition != envs[0].definition:
                raise RuntimeError(f"Godot on port {env.connection.port} defines different spaces than port {envs[0].connection.port}")
        self.pool = ThreadPoolExecutor(max_workers=self.num_envs)

    def reset(self) -> list[np.ndarray]:
        seeds = [self.rng.randrange(1 << 30) for _ in self.envs]
        results = self.pool.map(lambda pair: pair[0].reset(seed=pair[1])[0], zip(self.envs, seeds))
        return list(results)

    def step(self, actions: list[int]):
        """Returns, per instance, (final_obs, reward, terminated, truncated, info, next_obs).

        final_obs is the observation the action led to; next_obs is where the instance continues,
        which is a fresh reset observation when the episode just ended.
        """
        seeds = [self.rng.randrange(1 << 30) for _ in self.envs]
        futures = [self.pool.submit(self._step_one, env, action, seed) for env, action, seed in zip(self.envs, actions, seeds)]
        # Wait for every instance before raising, so no thread is still using its socket.
        errors = [future.exception() for future in futures]
        for error in errors:
            if error is not None:
                raise error
        return [future.result() for future in futures]

    @staticmethod
    def _step_one(env: GodotGridEnv, action: int, seed: int):
        observation, reward, terminated, truncated, info = env.step(action)
        next_observation = observation
        if terminated or truncated:
            next_observation, _ = env.reset(seed=seed)
        return observation, reward, terminated, truncated, info, next_observation

    def notify(self, message: dict) -> None:
        for env in self.envs:
            env.connection.notify(message)

    def close(self) -> None:
        self.pool.shutdown(wait=True)
        for env in self.envs:
            env.connection.close_session()
            env.connection.close()


def state_key(observation) -> str:
    """Rounds each value to a grid cell, as the exported ONNX model does."""
    return ",".join(str(int(round(float(v)))) for v in observation)


def save_policy(path: Path, definition: dict, q_table: dict, episodes: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "format": POLICY_FORMAT,
        "observation_space": definition["observation_space"],
        "action_space": definition["action_space"],
        "episodes": episodes,
        "q": {key: [float(v) for v in values] for key, values in q_table.items()},
    }
    path.write_text(json.dumps(data, indent=1), encoding="utf-8")


def export_onnx_policy(policy_path: Path, onnx_path: Path) -> None:
    try:
        from export_onnx import export
    except ImportError as error:
        print(f"skipped ONNX export: {error}", file=sys.stderr)
        return
    checked = export(policy_path, onnx_path)
    print(f"exported ONNX policy to {onnx_path} ({checked} states checked)")


def train(vec: GodotVectorEnv, args: argparse.Namespace) -> tuple[dict, int]:
    n_actions = int(vec.action_space.n)
    q_table: dict[str, list[float]] = {}
    rng = random.Random(args.seed)
    completed = 0
    steps = 0
    started = time.monotonic()
    last_progress = 0.0
    totals = [0.0] * vec.num_envs
    recent: list[tuple[float, str]] = []

    def epsilon() -> float:
        return max(args.epsilon_min, math.exp(-4.0 * completed / args.episodes))

    try:
        observations = vec.reset()
        while completed < args.episodes:
            eps = epsilon()
            keys = [state_key(observation) for observation in observations]
            actions = []
            for key in keys:
                values = q_table.setdefault(key, [0.0] * n_actions)
                actions.append(rng.randrange(n_actions) if rng.random() < eps else int(np.argmax(values)))

            results = vec.step(actions)
            steps += vec.num_envs
            for index, (key, action, result) in enumerate(zip(keys, actions, results)):
                final_observation, reward, terminated, truncated, info, next_observation = result
                values = q_table[key]
                final_values = q_table.setdefault(state_key(final_observation), [0.0] * n_actions)
                target = reward if terminated else reward + args.gamma * max(final_values)
                values[action] += args.alpha * (target - values[action])
                totals[index] += reward
                observations[index] = next_observation
                if terminated or truncated:
                    completed += 1
                    recent.append((totals[index], info.get("outcome", "done")))
                    totals[index] = 0.0

            now = time.monotonic()
            if now - last_progress >= PROGRESS_INTERVAL_SEC or completed >= args.episodes:
                last_progress = now
                vec.notify({
                    "type": "progress",
                    "episode": min(completed, args.episodes),
                    "episodes": args.episodes,
                    "epsilon": eps,
                    "states": len(q_table),
                    "instances": vec.num_envs,
                })
            if len(recent) >= 50:
                successes = sum(1 for _, outcome in recent if outcome == "success")
                mean = sum(total for total, _ in recent) / len(recent)
                rate = steps / max(now - started, 1e-6)
                print(f"episodes {completed:5d}  mean reward {mean:7.2f}  success {successes:2d}/{len(recent)}  "
                      f"epsilon {eps:.2f}  states {len(q_table)}  {rate:6.0f} steps/s over {vec.num_envs} instance(s)")
                recent.clear()
    except StopRequested as stop:
        print(f"Godot asked to stop after {completed} episodes: {stop}")
    except (ConnectionError, OSError) as error:
        print(f"lost an instance after {completed} episodes, saving what was learned: {error}", file=sys.stderr)
    elapsed = time.monotonic() - started
    print(f"trained {completed} episodes, {steps} steps in {elapsed:.1f} s ({steps / max(elapsed, 1e-6):.0f} steps/s)")
    return q_table, completed


def connect_all(args: argparse.Namespace) -> list[GodotGridEnv]:
    """Connects to every port at once, so slow-starting instances do not delay each other."""
    with ThreadPoolExecutor(max_workers=len(args.port)) as pool:
        futures = [pool.submit(GodotConnection, args.host, port, args.connect_timeout) for port in args.port]
        connections = []
        error = None
        for future in futures:
            try:
                connections.append(future.result())
            except ConnectionError as failure:
                error = error or failure
    if error is not None:
        for connection in connections:
            connection.close()
        raise error
    envs = []
    try:
        for connection in connections:
            envs.append(GodotGridEnv(connection))
    except BaseException:
        for connection in connections:
            connection.close()
        raise
    return envs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, nargs="+", default=[8000], help="One port per Godot instance")
    parser.add_argument("--episodes", type=int, default=300, help="Total episodes across all instances")
    parser.add_argument("--policy-out", type=Path, default=Path(__file__).resolve().parent.parent / "policies" / "q_policy.json")
    parser.add_argument("--onnx-out", type=Path, help="Also export the policy to ONNX (needs the onnx package)")
    parser.add_argument("--alpha", type=float, default=0.5)
    parser.add_argument("--gamma", type=float, default=0.95)
    parser.add_argument("--epsilon-min", type=float, default=0.05)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--connect-timeout", type=float, default=30.0)
    args = parser.parse_args()
    if len(set(args.port)) != len(args.port):
        parser.error("each Godot instance needs its own port")

    print(f"connecting to {len(args.port)} Godot instance(s) on {args.host} ports {args.port} ...")
    try:
        envs = connect_all(args)
    except (ConnectionError, RuntimeError, StopRequested) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    vec = GodotVectorEnv(envs, random.Random(args.seed + 1))
    print(f"observation space: {vec.observation_space}")
    print(f"action space:      {vec.action_space}")
    try:
        q_table, completed = train(vec, args)
        save_policy(args.policy_out, envs[0].definition, q_table, completed)
        print(f"saved policy with {len(q_table)} states to {args.policy_out}")
        if args.onnx_out is not None:
            export_onnx_policy(args.policy_out, args.onnx_out)
        vec.notify({"type": "saved", "path": str(args.policy_out)})
    except (RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        vec.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
