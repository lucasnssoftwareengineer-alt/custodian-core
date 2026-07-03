# 2. Custody vocabulary

Date: 2026-07-02

## Status

Accepted

## Context

Following [0001](0001-domain-agnostic-core.md), `custodian-core` must stay
domain-agnostic, but it still needs a vocabulary of its own to describe the
mechanism it implements: something needs to be resolved, and someone takes on
resolving it.

Generic terms borrowed from adjacent domains were considered, notably
"backer" and "contract" (evoking crowdfunding or legal/financial agreements).
These carry connotations that are misleading here: a "backer" implies
committed capital, and a "contract" implies a bilateral, negotiated,
enforceable agreement with legal weight. Neither matches what this gem
actually models, which is closer to a duty of care being taken on and
potentially handed off — the same shape as a guardianship or custody chain.

## Decision

We adopt vocabulary drawn from the domain of guardianship and custody:

- **custodian** — the party who takes on responsibility for resolving
  something.
- **ward** — the party or thing being protected or resolved.
- **Custody** — the agreement/relationship between a custodian and a ward at
  a given point in the chain. This replaces the more generic "contract".

A `Node` represents the ward's position in the tree of responsibilities. A
`Custody` represents a custodian having taken on that node, with the ability
to invoke an action.

## Consequences

- All future public API, class, and method names in `custodian-core` should
  draw from this vocabulary (custodian, ward, custody, chain) rather than
  introducing new generic or domain-specific synonyms.
- The vocabulary is intuitive and self-explanatory regardless of which
  concrete domain a satellite gem applies it to (money, storage, networking,
  etc.), which reinforces the domain-agnostic constraint from
  [0001](0001-domain-agnostic-core.md): the words themselves never assume a
  domain.
- Documentation and code comments should prefer "custodian"/"ward"/"custody"
  over generic alternatives like "backer"/"contract"/"owner" to keep the
  mental model consistent across the whole project.
