# 5. Binary nodes as magnitude firewalls in aggregation

Date: 2026-07-07

## Status

Accepted

## Context

`Adjuster.aggregate_demand` computes, for every node in a subtree, its
consolidated numeric demand: a node's `aggregated_demand` is its own
`demand_value` plus the `aggregated_demand` of its numeric children.

A binary node has no magnitude at all (per
[ADR 0002](0002-custody-vocabulary.md)'s vocabulary, it represents "this
must be done," not a quantity). It can still have numeric children of its
own — a binary obligation whose internal sub-parts happen to be quantified.
The question is: should those numeric grandchildren's demand flow through
the binary node and count toward the binary node's numeric grandparent?

## Decision

No. A binary node is a magnitude firewall: quantities never pass through
it in either direction during aggregation. Concretely:

- A binary node's own `aggregated_demand` is always `nil` — it contributes
  nothing to its parent's sum, regardless of what its own children add up
  to internally.
- A numeric node's aggregation only ever sums its *direct* children's
  `aggregated_demand`, and only for children that are not binary. A
  numeric grandchild under a binary parent never reaches the numeric
  grandparent's total.

Binary nodes are still counted, separately, via `unresolved_binary_count` —
every node's count includes itself (if binary) plus its subtree's binary
nodes — so the aggregation still answers "are there binary obligations
pending under this branch," just not "how much do they weigh."

This firewall is scoped specifically to **aggregation** (`aggregate_demand`,
a pure read-only calculation). It does not describe escalation. Escalation
(the live resolution walk in `Adjuster.resolve_tree`, see
[ADR 0006](0006-escalation-with-per-level-encapsulation.md)) still lets a
numeric child's unresolved shortfall cross into a binary direct parent,
because escalation is asking a different question ("who resolves this
next") rather than "what does this branch weigh in total." Aggregation and
escalation are different mechanisms with different rules, and this
distinction is deliberate, not an inconsistency — see the integration spec
in `spec/integration/full_resolution_spec.rb` for an explicit assertion of
both halves of this contrast in the same tree.

## Consequences

- Aggregation numbers are stable and predictable: a numeric node's
  aggregated total only ever reflects the numeric magnitude actually
  reachable without crossing a binary boundary — no double-counting, no
  silently-included internal breakdown of an indivisible obligation.
- Callers who need "does this branch have unresolved binary work" use
  `unresolved_binary_count`; callers who need "how much numeric magnitude
  is outstanding" use `aggregated_demand`. These are two independent
  questions and the API keeps them independent.
- Because escalation does NOT follow this same firewall, a reader must not
  assume "binary nodes block everything" — they block aggregation
  specifically. This is documented here and in the Adjuster's own code
  comments to prevent the two mechanisms' rules from being conflated.
