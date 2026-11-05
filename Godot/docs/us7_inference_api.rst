Setting Up Inference in Godot
=============================

This guide explains how to run a trained Schola policy inside Godot without Python, and how to ship
it in an exported game.

.. note::

    This guide assumes you have already trained an agent with Schola and exported the policy to ONNX.

.. note::

    Inference runs on the CPU with ONNX Runtime 1.30.0 through its C API. The supported observation
    and action spaces are Box, Discrete, MultiDiscrete, MultiBinary, and a Dict of those spaces.
    Nested Dict spaces are not supported, matching the Python exporter.


Install ONNX Runtime
--------------------

ONNX Runtime is not committed to the repository. Download the pinned package once before building:

.. code-block:: bash

    python Godot/tools/setup_onnxruntime.py
    scons -C Godot platform=<PLATFORM> target=template_debug
    scons -C Godot platform=<PLATFORM> target=template_release

The ``template_release`` build is only needed for release exports. The script reads
``Godot/dependencies.lock.json``, downloads Microsoft's prebuilt package for your platform, verifies
its SHA-256 checksum, and unpacks it into the git-ignored
``Godot/thirdparty/onnxruntime/``. The build links ONNX Runtime into the ``schola`` runtime extension
only and copies its library next to ``schola`` in ``addons/schola/bin/<PLATFORM>/``. The training
extension never links it.

Supported packages are Windows x86_64, Linux x86_64, and macOS arm64. ONNX Runtime has no universal
macOS package, so macOS builds use ``platform=macos arch=arm64``.


Export a Policy to ONNX
-----------------------

Use Schola's Python tools to export a checkpoint if training did not export one:

.. tabs::

    .. group-tab:: Stable Baselines 3

        .. code-block:: bash

            schola sb3 export --policy-checkpoint-path <CHECKPOINT_PATH> --output-path <ONNX_PATH> --algorithm <ALGORITHM>

    .. group-tab:: Ray RLlib

        .. code-block:: bash

            schola rllib export --policy-checkpoint-path <CHECKPOINT_DIR> [--output-path <OUTPUT_DIR>]

Copy the ``.onnx`` file anywhere inside your Godot project, for example ``res://models/agent.onnx``.
Godot does not import ``.onnx`` files; Schola reads them directly.


Setting up Your Godot Scene
---------------------------

Schola's Godot inference consists of three components:

1. **Agent** - A :cpp:class:`ScholaAgent` node that declares its observation and action spaces and
   implements ``_observe()`` and ``_act()``
2. **Policy** - A :cpp:class:`ScholaOnnxPolicy` resource that loads the ONNX model and runs it
3. **Stepper** - A :cpp:class:`ScholaInferenceStepper` node that runs observe, infer, and act for its
   agents every physics frame and keeps one policy state per agent

Step 1: Configure the Agent
^^^^^^^^^^^^^^^^^^^^^^^^^^^

Add a :cpp:class:`ScholaAgent` node, set its ``observation_space`` and ``action_space`` in the
Inspector to the same spaces used during training, and attach a script:

.. code-block:: gdscript

    extends ScholaAgent

    func _observe() -> Variant:
        return PackedFloat32Array([global_position.x, global_position.y, velocity.x])

    func _act(action: Variant) -> void:
        velocity.x = action[0] * speed

``_observe()`` returns a value matching the observation space, and ``_act()`` receives a value
matching the action space.

Step 2: Create the Policy
^^^^^^^^^^^^^^^^^^^^^^^^^

Create a :cpp:class:`ScholaOnnxPolicy` resource (**New Resource > ScholaOnnxPolicy**) and save it as a
``.tres`` file:

- ``model_path`` - The ``.onnx`` file, for example ``res://models/agent.onnx``
- ``max_state_sequence_length`` - Only for recurrent models with a sequence of states; see
  `Recurrent ONNX Models`_

One policy resource can serve any number of agents that share the same spaces.

Step 3: Add the Stepper
^^^^^^^^^^^^^^^^^^^^^^^

Add a :cpp:class:`ScholaInferenceStepper` node and set:

- ``policy`` - The policy resource from Step 2
- ``agents`` - The agent nodes it drives
- ``enabled`` - Turn stepping off without removing the node, for example during a cutscene

When the game runs, the stepper loads the policy, initializes it from the first agent's spaces, adds
every agent in the list, and steps them every physics frame. Nothing runs in the editor.

Agents can also be added and removed while the game runs, for example when enemies spawn or die:

.. code-block:: gdscript

    $ScholaInferenceStepper.add_agent($Enemy)       # Returns OK or an Error.
    $ScholaInferenceStepper.remove_agent($Enemy)    # Returns how many entries were removed.

The same agent can be added more than once; each entry gets its own state, and ``remove_agent()``
and ``reset_state()`` affect every entry of that agent.

A few rules keep this safe:

- The ``agents`` list is only read when the game starts. After that, use ``add_agent()``.
- Add an agent to the scene before calling ``add_agent()``.
- To remove an agent inside ``_observe()`` or ``_act()``, use ``queue_free()``. Removing it
  immediately can skip an agent or give one the wrong action for that frame.
- ``remove_child()`` and ``reparent()`` also remove the agent from the stepper. Call ``add_agent()``
  again afterwards.
- Do not call ``free()`` on the stepper or its parent from an agent's ``_observe()`` or ``_act()``.
  Use ``queue_free()``.


Using a Policy Without a Stepper
--------------------------------

For a custom loop, such as a turn-based game, call the policy directly:

.. tabs::

    .. group-tab:: GDScript

        .. code-block:: gdscript

            @export var policy: ScholaOnnxPolicy
            var state: ScholaPolicyState

            func _ready() -> void:
                policy.initialize($Enemy)
                state = policy.create_state()

            func take_turn() -> void:
                var action = policy.infer($Enemy._observe(), state)
                $Enemy._act(action)

    .. group-tab:: C++

        .. code-block:: cpp

            schola::OnnxPolicy policy;
            policy.load_model(bytes.data(), bytes.size(), "agent.onnx");
            policy.init(definition);

            std::unique_ptr<schola::PolicyState> state;
            policy.create_initial_state(state);

            schola::Point action = definition.action_space.make_point();
            policy.think(observation, *state, action);

``initialize()`` loads the model if none is loaded yet, or if ``model_path`` or
``max_state_sequence_length`` changed since the last load. It then reads the agent's spaces and
checks that they fit the model. It must be called before ``create_state()`` and ``infer()``. For a
model without memory, the ``state`` argument of ``infer()`` can be omitted.

Call ``load()`` earlier, for example during a loading screen, to avoid a pause when the first agent
appears, or call it again to reload after changing ``model_path``.


Recurrent ONNX Models
---------------------

:cpp:class:`ScholaOnnxPolicy` treats model inputs whose names begin with ``state_in`` and outputs
whose names begin with ``state_out`` as recurrent state tensors, for example ``state_in_h`` and
``state_out_h``. Inputs and outputs are paired in model order, so the model must expose the same
number of each, and every state tensor must be float. Models without these tensors are stateless and
``is_recurrent()`` returns false.

Each agent's state starts at zero. Every successful inference reads the agent's state, and the model
writes the new state into a separate pending entry that is committed only after that inference
succeeds. A failed inference leaves that agent's state unchanged, but if a stepper fails partway
through a step, the agents before the failing one keep their new state.

If a state input has a dynamic sequence dimension right after the batch dimension, the state keeps
a history of ``max_state_sequence_length`` entries. Each step drops the oldest entry and appends the
newest one. ONNX Runtime cannot read the ``max_seq_len`` metadata that the exporter attaches to each
state input, so set ``max_state_sequence_length`` to the value used in training. The default is one.
A wrong value gives wrong actions with no error. RLlib LSTM exports have no sequence dimension, so
they do not use this setting.

Call ``reset_state(agent)`` or ``reset_states()`` on the stepper, or ``reset()`` on a
:cpp:class:`ScholaPolicyState`, when an agent's episode restarts.

.. note::

    After ``load()``, states created for the previous model are still accepted if the new model's
    state tensors have the same sizes, and rejected otherwise. Create new states with
    ``create_state()`` after every reload.


Policy State Lifecycle
----------------------

:cpp:class:`schola::PolicyState` is the data a policy carries from one inference step to the next,
such as recurrent tensors. It does not hold the policy, so one policy serves many agents while each
agent keeps its own state.

The policy creates the initial state through ``create_initial_state()``. The caller owns it and
passes the same object to every ``think()`` call for that agent; ``think()`` advances it in place.
:cpp:class:`schola::SimpleStepper` owns one state per entry, and :cpp:class:`ScholaPolicyState` owns
one state for GDScript.

Policies without memory create an :cpp:class:`schola::EmptyPolicyState`, so a state is never null.
``copy_from()`` copies another state of the same type and size, and ``reset()`` returns a state to
the start of an episode.


Model Contract
--------------

The Godot runtime expects the layout produced by Schola's Python exporter. Dimension 0 is a dynamic
batch dimension.

.. list-table::
    :header-rows: 1

    * - Space
      - Tensor name
      - Input element type
      - Output element type
      - Shape
    * - Box
      - ``obs`` / ``action``, or the Dict key
      - Any numeric type
      - ``float`` or ``double``
      - ``[batch, *shape]``
    * - Discrete
      - ``obs`` / ``action``, or the Dict key
      - ``int64`` or ``int32``
      - ``int64`` or ``int32``
      - ``[batch]``
    * - MultiDiscrete
      - ``obs`` / ``action``, or the Dict key
      - ``int64`` or ``int32``
      - ``int64`` or ``int32``
      - ``[batch, n]``
    * - MultiBinary
      - ``obs`` / ``action``, or the Dict key
      - ``int8``, ``uint8``, or ``bool``
      - ``bool``, ``int8``, or ``uint8``
      - ``[batch, n]``

Every non-state model input and output must match a space, and every space must match a tensor.
Otherwise ``initialize()`` fails and names the mismatched tensor.

Box actions are clamped to the action space, because trained models can output values past its
bounds. A Discrete or MultiDiscrete action outside its space is not changed: the stepper rejects it
for that agent only, and ``infer()`` returns it as it is.

.. note::

    With RLlib's default ``normalize_actions``, training rescales Box actions to the bounds, but the
    exported model does not. Use Box action bounds of -1 to 1 with RLlib.


Errors
------

Errors never stop the game:

- Methods that can fail return a Godot ``Error``. ``infer()`` and ``create_state()`` return
  ``null`` instead.
- Every failure is printed with ``push_error()``, prefixed with the class and method, such as
  ``ScholaOnnxPolicy.load: cannot read 'res://enemy.onnx'``. The stepper prints a repeated failure
  only once, until a step succeeds or the message changes.
- :cpp:class:`ScholaOnnxPolicy` and :cpp:class:`ScholaPolicyState` keep the message of the last
  failed call in ``get_last_error()``. Each call that can fail clears it first, so read it right
  after the call.
- :cpp:class:`ScholaInferenceStepper` runs on its own, so it also emits
  ``inference_failed(message)``. If one agent's ``_observe()`` or ``_act()`` fails, the other agents
  still act, and an agent whose ``_observe()`` failed reuses its last observation. Errors during the
  stepper's startup fire before a parent's ``_ready()`` runs, so connect the signal in the Inspector
  to catch them.
- If the stepper's ``policy`` is replaced, the stepper removes its agents and reports an error; add
  the agents again. During a step, inside ``_observe()`` or ``_act()``, the change is rejected with
  an error; use ``set_deferred("policy", value)`` instead.
- If the policy is reloaded with ``load()``, every step fails until you call ``initialize()`` again,
  or remove all agents and add them back. If the spaces changed, remove all agents first.
- An agent that leaves the scene tree is removed automatically.
- The Inspector shows a warning on a :cpp:class:`ScholaInferenceStepper` without a policy, with an
  empty ``model_path``, or with an agent path that is not a :cpp:class:`ScholaAgent`.

.. list-table::
    :header-rows: 1

    * - Error
      - Meaning
    * - ``ERR_FILE_NOT_FOUND``
      - The file at ``model_path`` does not exist
    * - ``ERR_FILE_CANT_OPEN``
      - ``model_path`` is empty or cannot be opened, such as a folder
    * - ``ERR_FILE_CORRUPT``
      - The file at ``model_path`` is empty
    * - ``ERR_INVALID_DATA``
      - The file is not a valid model, the model does not fit the agent's spaces, or an agent's spaces
        differ from the other agents in the stepper
    * - ``ERR_INVALID_PARAMETER``
      - A value does not match its space, or a state does not fit the model
    * - ``ERR_UNCONFIGURED``
      - A required step was skipped, such as ``initialize()`` before ``infer()``
    * - ``FAILED``
      - The model failed to run


Exporting Your Game
-------------------

The runtime add-on ``addons/schola/`` declares ONNX Runtime as a dependency in
``schola.gdextension``, so Godot copies the library next to the extension in exported games. Two
export preset settings are required under **Project > Export > Resources**:

1. **Filters to export non-resource files/folders**: add ``*.onnx``. Godot does not export
   ``.onnx`` files by default.
2. **Filters to exclude files/folders**: add ``addons/schola_training/*``. Shipped games do not need
   the training add-on.

``ScholaOnnxPolicy.load()`` reads the model with ``FileAccess``, so ``res://`` paths work inside the
exported ``.pck``. Paths such as ``user://`` or an absolute file path also work.

Release exports need the ``template_release`` build of the extension; without it, the export fails.


Differences from Unreal Schola
------------------------------

The Godot runtime follows the policy state design of Unreal Schola, with these differences:

- Core C++ functions return :cpp:class:`schola::Status` instead of logging, and Godot methods return
  ``Error``.
- ``SimpleStepper::add_agent()`` reports the new index through an output parameter.
- :cpp:class:`ScholaInferenceStepper` takes agent nodes instead of indices.
- Models load from bytes through ``FileAccess`` instead of an imported asset.
- There is no pipelined stepper; inference runs synchronously on the main thread.
