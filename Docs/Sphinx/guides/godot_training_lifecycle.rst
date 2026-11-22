Godot Training Lifecycle
========================

Schola coordinates a fixed set of Godot environments through one training
session. The lifecycle layer orders environment definitions, resets, steps, and
shutdown without exposing networking details to environment scripts.

Session sequence
----------------

The training integration calls ``ScholaTrainingHost`` in this order:

#. ``initialize_session()`` discovers configured ``ScholaEnvironment`` nodes.
#. ``set_autoreset_mode()`` selects disabled, same-step, or next-step autoreset.
#. ``define()`` initializes each environment and returns the training definition.
#. ``reset()`` starts an episode in every environment.
#. ``step()`` advances the active environments.
#. ``close()`` releases the session. Leaving the scene tree also closes it.

Every Godot-facing call returns a dictionary with this shape::

    {
        "status": {
            "code": 0,
            "message": ""
        },
        "value": result_or_null
    }

Callers must check ``status.code`` before reading ``value``. A failed operation
does not publish a partially updated definition, reset state, or step result.

Environment identity and ordering
---------------------------------

The host discovers environments in deterministic scene-tree order. Their
zero-based positions become their environment IDs, and that mapping remains
fixed until the session closes. Adding, freeing, or removing an environment
during a session is unsupported. If a configured node disappears, the host
closes the session instead of assigning its ID to another environment.

Dynamic agent membership
------------------------

Environment nodes must not be nested, even through grouping nodes. A nested
``ScholaEnvironment`` reports an Inspector warning and training rejects the
configuration. Multiple separate, non-nested environments in a scene are valid.

The training definition contains all possible agent IDs and their fixed spaces.
Override ``ScholaEnvironment._get_possible_agents()`` to return definition-template
nodes for future spawns; by default, the initial descendants supply definitions.
Only live descendants participate. Reset rediscovers nodes after the reset hook,
so episodes may start with different subsets and replacement node instances.
Reset also discovers births from initial observation callbacks and removes agents
that leave during those callbacks before publishing the initial population.

Set an explicit ``agent_id`` for each possible agent so Godot node name collisions
cannot change its identity. New descendants receive an initial observation and
zero reward and act on the next step.

In dynamic environments, departing agents keep any observation, reward, and info
already collected that step. For an external cutoff, return ``truncated: true``
from ``_get_step_result()`` before the node leaves. Departures without a collected
result use the previous observation and zero reward and are marked terminated.
An agent whose action was skipped because it was absent still finishes if it is
reattached later in the step. In a fixed-population environment, freeing or
removing an agent causes a training error.

Changing a pending agent's resolved ID before action dispatch closes the session
without applying the stale action. Retired IDs are ignored until reset. Replacing
a still-active node with another using the same ID closes the session. Use a
fresh declared ID for each respawn that should act within the same episode, such
as ``player_spawn_2`` after ``player_spawn_1``. IDs can be reused after reset.
Unused possible IDs do not hold an episode open. Completion occurs when every
observed agent finishes.

Use a Python client supporting dynamic rosters, such as RLlib. Fixed-size SB3
vector interfaces still require a fixed population. Definitions are exchanged
once; arbitrary new IDs or changed spaces require a new training definition.

Temporary training pauses
-------------------------

Set ``ScholaAgent.training_paused`` to suspend training callbacks without
terminating the agent. Clear it to resume the same ID and node. The property does
not pause Godot processing or physics, and reset preserves it unless the game's
reset hook changes it.

Actions must still match the last published roster. An already-requested action
is skipped if the node is paused at dispatch. A transition whose action or
observation was already collected is published once before the pause takes
effect; an action that ran finishes its normal result hook. Subsequent responses omit paused agents, so their
actions must also be omitted. Resuming produces a fresh observation with zero
reward; the agent acts on the following step. Observed paused agents prevent
episode completion. Empty action maps are valid when every participant is paused.
Initially paused agents enter only after resuming and being observed.

Removal still terminates a paused agent. Finished IDs cannot resume until reset,
and replacing a paused node with a different node using the same ID is invalid.
Use the updated Schola RLlib adapters, which distinguish ready agents from episode
participants. SB3's fixed-size interface does not support training pauses.

Episode completion
------------------

An environment reports ``terminated`` when an agent reaches a terminal state
and ``truncated`` when an external condition ends an otherwise unfinished
episode. The lifecycle becomes complete only after every agent is terminated or
truncated.

The lifecycle host does not impose a maximum episode length. An environment
that needs a time limit must count its own steps and report ``truncated`` when
the limit is reached. The lifecycle keeps an episode step counter for
coordination and diagnostics, but the counter never changes completion flags.

Autoreset modes
---------------

``DISABLED``
    Completed environments retain their final state and are not stepped again
    until an explicit reset.

``SAME_STEP``
    The step result preserves the terminal state and also returns the new
    episode's initial observation separately.

``NEXT_STEP``
    The first call after completion resets the environment instead of consuming
    its action. The returned state contains the initial observation, zero reward,
    and cleared completion flags.

Automatic resets use default reset settings. Seed and option values supplied to
an explicit reset are not reused for later automatic resets.

Failure and shutdown behavior
-----------------------------

The session is atomic. A failure after an environment may have mutated faults
and closes the complete session. Validation failures detected before environment
execution return an error without publishing output. Schola does not continue
with a smaller environment set because doing so would change the IDs observed
by Python. ``close()`` is idempotent and is safe after normal work, partial
startup, or a previous failure.

All scene-tree access and environment callbacks run on Godot's main thread.
Transport, gRPC scheduling, and graceful failure notification to Python belong
to the training connector rather than the lifecycle host.
