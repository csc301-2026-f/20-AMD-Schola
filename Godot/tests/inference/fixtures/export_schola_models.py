#!/usr/bin/env python3
# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

"""
Exports small untrained Stable-Baselines3 PPO policies and an RLlib LSTM policy with Schola's own ONNX
exporter, to check that the Godot inference reads what Python actually produces.

Next to each model, <name>.expected.txt holds observations and the actions ONNX Runtime returns for them:
    observation <values...>
    action <values...>
The LSTM file repeats one observation for several steps, so its actions only change through its memory.
The memory model keeps a window of past observations, so its actions depend on the declared sequence length.

Regenerate with the Schola Python package installed (pip install -e "./Resources/python[sb3,rllib]"):
    python Godot/tests/inference/fixtures/export_schola_models.py [names...]
The committed files were made with onnxruntime 1.30.0 and torch 2.14.0; other versions change the bytes.
"""

import sys
from pathlib import Path

import gymnasium as gym
import numpy as np
import onnxruntime
import torch as th
from schola.core.model import ScholaModel, StateMetadata
from schola.sb3.export import SB3PPOModel
from schola.sb3.utils import merge_spaces
from stable_baselines3.common.policies import (
    ActorCriticPolicy,
    MultiInputActorCriticPolicy,
)

FIXTURES_DIRECTORY = Path(__file__).resolve().parent
LSTM_MODEL = "schola_rllib_lstm"
LSTM_STEPS = 6
MEMORY_MODEL = "schola_memory_seq"
MEMORY_LENGTH = 4

MODELS = {
    "schola_ppo_discrete": (
        gym.spaces.Box(-1.0, 1.0, (4,), np.float32),
        gym.spaces.Discrete(3),
        {"obs": np.array([[0.5, -0.25, 0.75, -1.0]], np.float32)},
    ),
    "schola_ppo_box": (
        gym.spaces.Box(-1.0, 1.0, (3,), np.float32),
        gym.spaces.Box(-1.0, 1.0, (2,), np.float32),
        {"obs": np.array([[0.1, 0.2, -0.3]], np.float32)},
    ),
    "schola_ppo_dict": (
        gym.spaces.Dict(
            {
                "position": gym.spaces.Box(-1.0, 1.0, (2,), np.float32),
                "target": gym.spaces.Box(-1.0, 1.0, (2,), np.float32),
            }
        ),
        gym.spaces.MultiDiscrete([3, 2]),
        {
            "position": np.array([[0.3, -0.6]], np.float32),
            "target": np.array([[-0.2, 0.9]], np.float32),
        },
    ),
    "schola_ppo_race_car": (
        gym.spaces.Dict(
            {
                "00000000:Track": gym.spaces.Box(-100000.0, 100000.0, (6,), np.float32),
                "00000001:Velocity": gym.spaces.Box(-np.inf, np.inf, (3,), np.float32),
                "00000002:Rays": gym.spaces.Box(0.0, 1.0, (75,), np.float32),
                "00000003:RoadAhead": gym.spaces.Box(0.0, 1.0, (3,), np.float32),
            }
        ),
        gym.spaces.Dict(
            {"00000000:Controls": gym.spaces.Box(-1.0, 1.0, (2,), np.float32)}
        ),
        {
            "00000000:Track": np.array([[0.2, -0.1, 1.0, 0.0, 0.0, 0.3]], np.float32),
            "00000001:Velocity": np.array([[0.5, 0.0, 0.1]], np.float32),
            "00000002:Rays": np.array(
                [[0.0, 1.0, 0.8] * 12 + [1.0, 1.0, 0.35] + [0.0, 0.0, 0.0] * 12],
                np.float32,
            ),
            "00000003:RoadAhead": np.array([[1.0, 0.4, 1.0]], np.float32),
        },
    ),
}


def export(name, observation_space, action_space):
    th.manual_seed(0)
    policy_class = (
        MultiInputActorCriticPolicy
        if isinstance(observation_space, gym.spaces.Dict)
        else ActorCriticPolicy
    )
    policy_action_space = (
        merge_spaces(*action_space.spaces.values())
        if isinstance(action_space, gym.spaces.Dict)
        else action_space
    )
    policy = policy_class(observation_space, policy_action_space, lambda _: 0.0)
    SB3PPOModel(policy, action_space).save_as_onnx(FIXTURES_DIRECTORY / f"{name}.onnx")


def write_expected(name, feeds):
    session = onnxruntime.InferenceSession(str(FIXTURES_DIRECTORY / f"{name}.onnx"))
    outputs = session.run(None, feeds)
    assert len(outputs) == 1, f"{name}: expected a single action output"
    observation = np.concatenate([value.reshape(-1) for value in feeds.values()])
    action = outputs[0].reshape(-1)
    lines = [
        "observation " + " ".join(repr(float(v)) for v in observation),
        "action " + " ".join(repr(float(v)) for v in action),
    ]
    (FIXTURES_DIRECTORY / f"{name}.expected.txt").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def export_lstm():
    from ray.rllib.algorithms.ppo.torch.default_ppo_torch_rl_module import (
        DefaultPPOTorchRLModule,
    )
    from ray.rllib.core.rl_module.rl_module import RLModuleSpec
    from schola.rllib.export import export_onnx_from_policy

    th.manual_seed(0)
    observation_space = gym.spaces.Box(-1.0, 1.0, (4,), np.float32)
    action_space = gym.spaces.Box(-1.0, 1.0, (2,), np.float32)
    module = RLModuleSpec(
        module_class=DefaultPPOTorchRLModule,
        observation_space=observation_space,
        action_space=action_space,
        model_config={
            "use_lstm": True,
            "lstm_cell_size": 16,
            "max_seq_len": 8,
            "fcnet_hiddens": [16],
        },
    ).build()
    path = FIXTURES_DIRECTORY / f"{LSTM_MODEL}.onnx"
    export_onnx_from_policy(module, path, observation_space, action_space)

    session = onnxruntime.InferenceSession(str(path))
    output_names = [output.name for output in session.get_outputs()]
    state = {
        tensor.name: np.zeros([1, *tensor.shape[1:]], np.float32)
        for tensor in session.get_inputs()
        if tensor.name.startswith("state_in")
    }
    observation = np.array([[0.5, -0.25, 0.75, -1.0]], np.float32)
    lines = []
    for _ in range(LSTM_STEPS):
        outputs = session.run(output_names, {"obs": observation, **state})
        for name, value in zip(output_names, outputs):
            if name.startswith("state_out"):
                state[name.replace("state_out", "state_in")] = value
        lines.append("observation " + " ".join(repr(float(v)) for v in observation[0]))
        lines.append("action " + " ".join(repr(float(v)) for v in outputs[0][0]))
    assert lines[1] != lines[-1], "the LSTM actions must change through its memory"
    (FIXTURES_DIRECTORY / f"{LSTM_MODEL}.expected.txt").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


class MemoryModel(ScholaModel):
    def __init__(self, observation_space, action_space):
        super().__init__(observation_space, action_space)
        self.encode = th.nn.Linear(4, 3)
        self.decode = th.nn.Linear(3, 2)

    @property
    def initial_state_dict(self):
        return {"memory": th.zeros(MEMORY_LENGTH, 3)}

    @property
    def state_metadata(self):
        return {
            "memory": StateMetadata(
                has_seq_dim=True, max_seq_len=MEMORY_LENGTH, seq_dim=1
            )
        }

    def forward(self, *args):
        obs, memory = args
        entry = th.tanh(self.encode(obs))
        return th.tanh(self.decode(entry + memory.sum(dim=1))), entry


def export_memory():
    th.manual_seed(0)
    observation_space = gym.spaces.Box(-1.0, 1.0, (4,), np.float32)
    action_space = gym.spaces.Box(-1.0, 1.0, (2,), np.float32)
    path = FIXTURES_DIRECTORY / f"{MEMORY_MODEL}.onnx"
    MemoryModel(observation_space, action_space).save_as_onnx(path)

    session = onnxruntime.InferenceSession(str(path))
    memory = np.zeros((1, MEMORY_LENGTH, 3), np.float32)
    lines = []
    for step in range(MEMORY_LENGTH + 2):
        observation = np.array([[0.5, -0.25, 0.75, -1.0]], np.float32) * (step + 1) / 6
        feeds = {"obs": observation, "state_in_memory": memory}
        action, entry = session.run(None, feeds)
        memory = np.concatenate([memory[:, 1:], entry[:, None]], axis=1)
        lines.append("observation " + " ".join(repr(float(v)) for v in observation[0]))
        lines.append("action " + " ".join(repr(float(v)) for v in action[0]))
    (FIXTURES_DIRECTORY / f"{MEMORY_MODEL}.expected.txt").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def main():
    selected = set(sys.argv[1:])
    for name, (observation_space, action_space, feeds) in MODELS.items():
        if selected and name not in selected:
            continue
        export(name, observation_space, action_space)
        write_expected(name, feeds)
        print(f"Exported {name}.onnx")
    for name, run in ((LSTM_MODEL, export_lstm), (MEMORY_MODEL, export_memory)):
        if not selected or name in selected:
            run()
            print(f"Exported {name}.onnx")
    print(
        f"onnxruntime {onnxruntime.__version__}, torch {th.__version__}, python {sys.version.split()[0]}"
    )


if __name__ == "__main__":
    main()
