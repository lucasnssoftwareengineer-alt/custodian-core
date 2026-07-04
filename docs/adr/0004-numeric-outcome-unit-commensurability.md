# 4. Numeric outcome unit commensurability

Date: 2026-07-03

## Status

Accepted

## Context

A future ActionRegistry will let registered actions return `:resolved`,
`:failed`, or a Numeric value representing partial resolution of a Node's
demand_value. Nothing prevents an action from returning a Numeric denominated
in a different unit than the Node's own demand_value (example: a Node
measuring water level in centimeters, whose registered action
"open_floodgates" naturally operates in cubic meters of discharge).
Subtracting mismatched units produces a number that is valid Ruby but
physically meaningless — a silent bug, not a crash.

## Decision

Any Numeric returned by a registered action MUST be expressed in the same
unit as the Node's demand_value. Unit conversion is entirely the
responsibility of the action itself (registered by a domain-specific
satellite gem or host app) — the core never knows units exist. If an action
cannot reliably guarantee this conversion, it must return `:resolved` or
`:failed` instead of attempting a Numeric partial result.

## Consequences

Domain gems registering actions with Numeric outcomes must document, for
each action, what unit the Node's demand_value is expected to be in. This is
a discipline enforced by documentation and code review, not by a runtime
type system (Ruby has no unit types) — flag this as a known limitation, not
a solved problem.
