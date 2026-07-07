## [Unreleased]

## [0.1.0] - 2026-07-07

Initial release: a domain-agnostic chain-of-custody engine over a tree of
responsibilities, ready for satellite gems to build concrete domains on top
of. 107 examples, 0 RuboCop offenses.

### Models

- `Node` — the ward: a tree (via `ancestry`) of binary or numeric demands,
  with a polymorphic `subject` (which may be another `Node`).
- `Graph` — a container anchored at a single root `Node`, with a
  polymorphic, optional `owner`.
- `Custody` — the agreement between a custodian and a ward: action name,
  priority, JSON action params, and a validity/status model
  (`eternal`/`fixed_term`/`punctual` × `active`/`at_risk`/`broken`/`expired`)
  exposed via `currently_valid?`, `trustworthy?`, and `healthcheck`.
- `CustodyNodeRule` / `CustodyRepudiatedNode` — per-descendant exceptions
  (`exclude`/`full`/`limit_pct`/`limit_amount` rules, and outright
  repudiations) that qualify how a `Custody` applies across its ward's
  subtree, surfaced through `Custody#applies_to?`.

### ActionRegistry

- The gem's one extension point: `register`/`unregister`/`call`/
  `registered?`/`clear!`, Symbol-normalized, Mutex-guarded.
- Strict outcome contract: `:resolved`, `:failed`, or a non-negative
  `Numeric`, in the same unit as the node's `demand_value`. Anything else —
  including negative Numerics — raises immediately rather than propagating
  a silent bug downstream.

### Adjuster

- `aggregate_demand` — pure, read-only consolidation of numeric demand
  across a subtree in a single query, with binary nodes acting as a
  magnitude firewall (they contribute no quantity to an ancestor's total,
  but are still counted via `unresolved_binary_count`).
- `resolve_tree` — walks a subtree post-order, consulting each node's
  direct custodies (filtered by caller-chosen `strictness: :valid` or
  `:trustworthy`, and by `Custody#applies_to?`), then registered phases,
  then escalating whatever remains to the direct parent with per-level
  encapsulation: a child's shortfall becomes part of its parent's own
  demand, with no marker distinguishing the two at invocation time. A
  grandparent never sees a grandchild; the full story is only
  reconstructable from each node's `attempts` audit trail. Binary
  escalation is supported too: a parent's custodians can be asked to act on
  a still-pending binary descendant's behalf.
- `register_phase` / `clear_phases!` — the hook a future sibling-generosity
  satellite will plug into. Not built yet; only the extension point is.
- Pure resolution throughout: neither method persists or mutates any
  record.

### Documentation

- README with the project's guiding definition, vocabulary, quick start,
  outcome contract, resolution order, and explicitly non-domain examples.
- Eight ADRs recording the project's design decisions, from the
  domain-agnostic-core constraint through registry defensiveness.
