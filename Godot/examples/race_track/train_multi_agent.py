# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
import argparse
from pathlib import Path
import sys

import numpy as np
import onnx
from onnx import numpy_helper
import schola.rllib.policy_mapping as policy_mapping
from schola.scripts.launch import main as schola

POLICY = Path(__file__).resolve().parent / "policies" / "race_track.onnx"
AGENT_TYPE = "race_car"
LOG_STD = -1.5
SCRATCH = ["--fcnet-hiddens", "64", "64", "--learning-rate", "0.0003"]
PRETRAINED = [
    "--fcnet-hiddens",
    "256",
    "256",
    "--activation",
    "tan-h",
    "--num-epochs",
    "2",
    "--learning-rate",
    "0.00001",
]


def read_policy(path):
    weights = {
        tensor.name: numpy_helper.to_array(tensor)
        for tensor in onnx.load(str(path)).graph.initializer
    }
    layers = {
        "encoder.actor_encoder.net.mlp.0": "policy.mlp_extractor.policy_net.0",
        "encoder.actor_encoder.net.mlp.2": "policy.mlp_extractor.policy_net.2",
        "pi.net.mlp.0": "policy.action_net",
    }
    state = {
        f"{target}.{part}": weights[f"{source}.{part}"].astype(np.float32)
        for target, source in layers.items()
        for part in ("weight", "bias")
    }
    weight = state["pi.net.mlp.0.weight"]
    bias = state["pi.net.mlp.0.bias"]
    state["pi.net.mlp.0.weight"] = np.concatenate([weight, np.zeros_like(weight)])
    state["pi.net.mlp.0.bias"] = np.concatenate([bias, np.full_like(bias, LOG_STD)])
    return state


def start_from(state):
    make_subclass = policy_mapping.schola_algorithm_subclass

    def make_pretrained(algo_class):
        base = make_subclass(algo_class)

        class Pretrained(base):
            def setup(self, config):
                super().setup(config)
                weights = self.learner_group.get_weights()
                for name, values in state.items():
                    needed = np.shape(weights[AGENT_TYPE][name])
                    if needed != values.shape:
                        raise ValueError(
                            f"{name} has shape {values.shape}, but the network needs {needed}"
                        )
                weights[AGENT_TYPE].update(state)
                self.learner_group.set_weights(weights)
                self.env_runner_group.sync_weights(
                    from_worker_or_learner_group=self.learner_group
                )

        return Pretrained

    policy_mapping.schola_algorithm_subclass = make_pretrained


def main():
    parser = argparse.ArgumentParser(
        description="Train the cars of race_track_multi_agent_train.tscn together with Schola's RLlib trainer."
    )
    parser.add_argument("--steps", type=int, default=100_000)
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument(
        "--pretrained",
        action="store_true",
        help="Start from the weights of policies/race_track.onnx instead of from scratch",
    )
    args = parser.parse_args()
    if args.pretrained:
        start_from(read_policy(POLICY))
    sys.argv = [
        "schola",
        "rllib",
        "train",
        "ppo",
        "--timesteps",
        str(args.steps),
        "--train-batch-size-per-learner",
        "2048",
        *(PRETRAINED if args.pretrained else SCRATCH),
        "editor",
        "--url",
        "127.0.0.1",
        "--port",
        str(args.port),
    ]
    schola()


if __name__ == "__main__":
    main()
