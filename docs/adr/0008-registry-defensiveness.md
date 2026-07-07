# 8. Registry defensiveness

Date: 2026-07-07

## Status

Accepted

## Context

`ActionRegistry` is the gem's one sanctioned extension point (per
[ADR 0001](0001-domain-agnostic-core.md)): every satellite gem and host app
reaches into the core exclusively through it. A plug-in registry like this
fails in two characteristic, hard-to-debug ways if it isn't careful:

1. **Silent overwrite.** If registering an action under a name that's
   already taken just replaces it quietly, two pieces of code that
   accidentally pick the same name produce a bug that only shows up as
   "the wrong thing happened," with no error anywhere near the actual
   mistake — often minutes or files away from where the second
   registration happened.
2. **Silent misuse.** If an action returns something outside the outcome
   contract (`:resolved`, `:failed`, or a non-negative `Numeric` — see
   [ADR 0004](0004-numeric-outcome-unit-commensurability.md)) and the
   registry just shrugs and passes it through, the bug surfaces arbitrarily
   far downstream — wherever the bad value is finally used — instead of at
   the call site that actually produced it.

## Decision

`ActionRegistry` refuses both, loudly, immediately:

- `register` raises `AlreadyRegisteredError`, naming the action, if the
  name is already taken. A host that genuinely wants to replace an
  existing action must call `unregister` first, explicitly. There is no
  quiet-overwrite path.
- `call` raises `InvalidOutcomeError`, naming the action and showing
  exactly what was returned, for anything that isn't `:resolved`,
  `:failed`, or a non-negative `Numeric` — including `true`, `nil`,
  Strings, and negative numbers (a negative Numeric would mean an action
  increased demand instead of covering it, which is never valid).
- `unregister` on a name that was never registered also raises
  `NotRegisteredError` rather than succeeding as a no-op — unregistering
  something that doesn't exist is almost always a typo, and a no-op would
  hide that.

The author's rationale, on record: in an environment where an increasing
share of the code touching this registry may be written by AI agents
working quickly and without full context, the registry cannot assume good
faith or careful reading on the part of every caller. An API that fails
fast and loud at the exact point of misuse — not three call frames later,
not in production, not as a support ticket — is not a nicety here; it is a
survival requirement for a plug-in boundary this central.

## Consequences

- Registering two actions under the same name is caught at registration
  time, at the exact call site, with the action name in the error message
  — not discovered later as "why is the wrong action running."
- An action that returns `true` instead of `:resolved` (an easy mistake)
  is caught the first time it's ever invoked, not after it's silently
  "resolved" things it never should have.
- This makes `ActionRegistry` slightly less forgiving to work with during
  rapid iteration (you cannot casually re-register the same name twice
  without calling `unregister`) in exchange for making misuse impossible
  to miss. Given this registry sits at the one boundary every satellite
  gem must cross, that trade is deliberate.
- Any future extension point added to this gem (e.g. `register_phase`,
  see [ADR 0006](0006-escalation-with-per-level-encapsulation.md)) should
  be held to the same standard: phases are validated with the exact same
  `ActionRegistry.validate_outcome!` rule as direct custodies, not a
  separate, looser one.
