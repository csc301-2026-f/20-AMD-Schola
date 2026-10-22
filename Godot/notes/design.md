# US4 Single-Environment Lifecycle Design

**Owner:** Shahyar Anfaz — single-environment lifecycle and `ScholaTrainingHost`
**Paired owner:** Guneev Pannu — coordinator and autoreset

## Design constraints

1. Preserve Python-visible reset, step, completion, and truncation behavior for one environment.
2. Accept normal engine-frame lag. A logical step does not promise that physical effects appear in the observation returned by the same call.
3. Python owns normal action-space and observation-space validation. Production lifecycle code does not exhaustively scan points.
4. Preserve completed-agent terminal state until reset.
5. Never leak episode-local state across reset.
6. Return owned lifecycle values that do not refer to mutable Godot storage.
7. Leave output parameters unchanged when an operation fails.

## Module boundary

Shahyar's implementation is engine-independent C++:

```text
Guneev's EnvironmentCoordinator
              |
              v
     EnvironmentLifecycle
              |
              v
       US1 Environment
```

It belongs in `Godot/src/core/lifecycle/environment_lifecycle.cpp` and implements the contract declared by `environment_lifecycle.h`. It must not include Godot, gRPC, Protocol Buffer, or ONNX Runtime headers.

## State machine

```text
UNINITIALIZED -> RESET_PENDING -> ACTIVE -> COMPLETE
                         ^          |
                         |----------|

Any environment-operation failure -> FAULTED
Any state --close()--> CLOSED
```

- `initialize()` discovers and stores the stable environment definition.
- `reset()` starts a new episode and clears the episode step count and cached state.
- `step()` executes one logical step and captures an owned state snapshot.
- The lifecycle becomes `COMPLETE` when every agent is terminated or truncated.
- `close()` releases episode-local state and is idempotent.

## Failure behavior

Precondition failures happen before calling the environment and leave the lifecycle state unchanged. Once an environment operation begins, a failure moves the lifecycle to `FAULTED` because the caller cannot prove that the environment remained unchanged. A faulted lifecycle rejects every operation except `close()`.

## Step limit

An episode step limit of zero disables step-based truncation. Otherwise, every successful step increments the count. When the limit is reached, agents that are neither terminated nor truncated are reported as truncated.

## Ownership boundaries

Guneev owns `EnvironmentCoordinator`, multiple-environment routing, and disabled, same-step, and next-step autoreset behavior.

Shahyar owns `ScholaTrainingHost`, the US4 Godot-facing composition boundary. It discovers the session's environments, constructs lifecycle instances, delegates batch and autoreset behavior to Guneev's coordinator, exposes bound methods to US3's `HostTrainingBackend`, and owns training-session startup and shutdown. It must not duplicate coordinator logic.
