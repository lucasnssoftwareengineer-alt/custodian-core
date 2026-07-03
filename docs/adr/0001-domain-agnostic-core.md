# 1. Domain-agnostic core

Date: 2026-07-02

## Status

Accepted

## Context

`custodian-core` implements a generic chain-of-custody mechanism over a tree
of responsibilities: a `Node` represents something that needs to be resolved
(the ward), and a `Custody` represents someone (a custodian) who took on
resolving it, calling an action if invoked.

This pattern is useful across many unrelated domains: money transfers waiting
on approval, files waiting on a storage backend, requests waiting on a
network handler, tasks waiting on a human reviewer, and so on. If we let any
one of these domains leak its vocabulary or logic into this gem, the core
stops being reusable and turns into a single-purpose library wearing a
generic name.

## Decision

`custodian-core` must never contain business logic specific to any concrete
domain. Concretely, this gem must never know about money, storage,
networking, or any other domain-specific vocabulary, workflow, or rule.

Concrete domains are implemented as separate satellite gems (e.g. a future
`custodian-payments`, `custodian-storage`, etc.). Satellite gems depend on
`custodian-core` and register their domain-specific actions into it through a
registry pattern (to be designed and implemented in a later step). The core
only knows about the shape of a chain of custody — who holds it, what it
protects, and that an action can be invoked — never about what that action
actually does or why.

This is a constraint that governs every future decision in this project. Any
change proposed for `custodian-core` should be checked against it: if a
change only makes sense in the context of one specific domain, it belongs in
a satellite gem, not here.

## Consequences

- `custodian-core` stays small, stable, and safe to depend on from unrelated
  domains at the same time.
- Domain logic changes (e.g. how a payment is authorized) never require a
  release of `custodian-core`, and vice versa.
- Every new capability considered for the core must be justified in
  domain-neutral terms. If it can't be explained without naming a concrete
  domain, it doesn't belong here.
- The registry pattern (introduced in a later step) becomes the only sanctioned
  extension point between satellite gems and the core.
