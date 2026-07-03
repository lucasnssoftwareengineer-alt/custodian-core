# 3. Adjuster naming

Date: 2026-07-03

## Status

Accepted

## Context

The class responsible for walking the custody chain needs a name. Its job is
to try direct `Custody` records by priority, run registered phases, and
escalate to the parent `Node` when unresolved.

"Engine" was initially considered, since it captures the idea of something
that drives resolution forward. However, `lib/custodian/core/engine.rb`
already defines `Custodian::Core::Engine` as the mandatory `Rails::Engine`
subclass required by the Rails engine convention (`isolate_namespace`,
autoloading, mountable structure — see [0001](0001-domain-agnostic-core.md)
for why this gem is a Rails engine at all). Reusing "Engine" for our
resolution class would collide with that constant in the same namespace.

## Decision

The resolution class is named `Adjuster` (`Custodian::Core::Adjuster`),
inspired by the insurance claims adjuster — a real-world role that reviews a
contract (policy), evaluates what happened, and determines who is
responsible for covering it. This maps precisely onto what the class does:
it reads a `Custody`, evaluates the `ActionRegistry` outcome
(`:resolved`/`:failed`/`Numeric`), and decides the next step in the chain.

## Consequences

**Positive:**

- No naming collision with `Rails::Engine`.
- The metaphor stays consistent with the custodian/ward/`Custody` vocabulary
  established in [0002](0002-custody-vocabulary.md).
- "Adjuster" doesn't carry the generic/overloaded meaning that "Resolver" or
  "Executor" would in a Ruby/Rails codebase.

**Negative:**

- "Adjuster" is a less common word than "Engine" or "Resolver", and might
  need a one-line explanation in the README for readers unfamiliar with
  insurance terminology.

## Alternatives considered

- **Resolver** — too generic, doesn't carry the contract-analysis metaphor.
- **Bailiff** — too legally hostile-sounding for the intended tone.
- **Arbiter** — implies adjudicating a dispute between equal parties, but
  this class doesn't judge disputes — it evaluates a single chain.
- **Executor** — dangerously overloaded term in Ruby/concurrency contexts;
  risk of confusing readers into thinking this relates to thread execution.

## Note

This ADR documents a naming decision made during planning. `Adjuster` does
not exist in `lib/` yet — it will be implemented in a future step once
`Custody`, `ActionRegistry`, and demand aggregation exist.
