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

Episode completion
------------------

An environment reports ``terminated`` when an agent reaches a terminal state
and ``truncated`` when an external condition ends an otherwise unfinished
episode. The lifecycle becomes complete only after every agent is terminated or
truncated.

US4 does not impose a maximum episode length. An environment that needs a time
limit must count its own steps and report ``truncated`` when the limit is
reached. The lifecycle keeps an episode step counter for coordination and
diagnostics, but the counter never changes completion flags.

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

The session is atomic: failure in any environment or coordinator operation
faults and closes the complete session. Schola does not continue with a smaller
environment set because doing so would change the IDs observed by Python.
``close()`` is idempotent and is safe after normal work, partial startup, or a
previous failure.

All scene-tree access and environment callbacks run on Godot's main thread.
Transport, gRPC scheduling, and graceful failure notification to Python belong
to the training connector rather than the lifecycle host.

Development status
------------------

The host and engine-independent lifecycle implementation are complete. Running
the host integration suite requires the Godot environment adapter supplied by
US1, including ``ScholaEnvironment::get_environment()``. Until that adapter is
available, the host sources compile but the runtime extension and end-to-end
host tests cannot be linked and executed.
