# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

"""Exercise Godot's dynamic roster with a real RLlib sampler over gRPC."""

import os
from pathlib import Path
import socket
import subprocess

import pytest
from ray.rllib.algorithms.ppo import PPOConfig

from schola.core.protocols.protobuf.grpc_protocol import GrpcProtocol
from schola.core.simulators.external_simulator import ExternalSimulator
from schola.rllib.env_runner import ScholaEnvRunner


@pytest.mark.timeout(60)
def test_sampler_resumes_all_paused_agents_and_samples_changed_reset_roster(tmp_path):
    godot = os.environ.get("SCHOLA_TEST_GODOT")
    if not godot:
        pytest.skip("Set SCHOLA_TEST_GODOT to run against the built Godot extensions")

    project = Path(__file__).resolve().parents[2] / "Godot"
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]

    config = (
        PPOConfig()
        .environment(
            env_config={
                "protocol": GrpcProtocol,
                "protocol_args": {
                    "url": "127.0.0.1",
                    "port": port,
                    "credential_mode": "insecure",
                    "environment_start_timeout": 15,
                },
                "simulator": ExternalSimulator,
            },
            disable_env_checking=True,
        )
        .env_runners(env_runner_cls=ScholaEnvRunner, num_env_runners=0)
        .multi_agent(
            policies={"shared"}, policy_mapping_fn=lambda *args, **kwargs: "shared"
        )
        .rl_module(model_config={"fcnet_hiddens": [8]})
    )

    log_path = tmp_path / "godot.log"
    with log_path.open("w") as log, subprocess.Popen(
        [
            godot,
            "--headless",
            "--path",
            str(project),
            "res://tests/integration/support/us4_sampler_environment.tscn",
            "--",
            f"-ScholaPort={port}",
        ],
        stdout=log,
        stderr=subprocess.STDOUT,
    ) as process:
        try:
            runner = ScholaEnvRunner(config=config, worker_index=0)
            try:
                episodes = runner.sample(num_episodes=2)
                assert [len(episode) for episode in episodes] == [5, 5]
                assert [set(episode.agent_episodes) for episode in episodes] == [
                    {"a"},
                    {"a", "b"},
                ]
                for episode in episodes:
                    assert episode.is_terminated
                    for agent in episode.agent_episodes.values():
                        # Only the first action and the action after resumption
                        # earn rewards, across five environment steps.
                        assert agent.get_return() == pytest.approx(2.0)
            finally:
                runner.stop()
        finally:
            process.terminate()
