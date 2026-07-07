# 6. Escalation with per-level encapsulation

Date: 2026-07-07

## Status

Accepted

## Context

When a node cannot fully resolve its own demand (after trying its direct
custodies and any registered phases), something has to happen to the
unresolved remainder. The simplest option would be to hand the caller a
flat list of every unresolved leaf across the whole tree, but that throws
away the tree's own shape: the entire point of a chain of custody is that
responsibility is delegated level by level, and each level should only
ever have to reason about its own direct reports, not the whole subtree
beneath them.

## Decision

Unresolved demand escalates exactly one level at a time, to the direct
parent, and it is *encapsulated* when it does:

- A numeric node's remaining shortfall is added to its direct parent's own
  demand **before** the parent is processed. When the parent's custodians
  are consulted, they are handed one combined `remaining` figure — there is
  no marker, flag, or separate argument distinguishing "the parent's own
  demand" from "what a child couldn't cover." From the custodian's point of
  view, it is simply asked to cover a number.
- A binary node's unresolved status escalates as a pending obligation: the
  parent's own custodians are asked, once per pending item, using the
  *original* node as the `node` argument (so the action knows what it's
  actually being asked to resolve) but the *parent's* custody (so it's
  clear whose custodian is acting). See
  [ADR 0002](0002-custody-vocabulary.md) — the custodian genuinely is
  acting on the ward's behalf here, not on its own.
- This repeats recursively. A node that itself fails to resolve what it
  inherited escalates the (now combined) remainder further up, one level
  at a time, until either something resolves it or the root is reached and
  reports a final, unresolved gap.

The consequence that gives this its name: a grandparent never sees a
grandchild. Each level of the tree only ever perceives one level down —
exactly the shape of a real management chain, where a manager doesn't need
to know which of their report's reports actually dropped the ball, only
that their own report came up short.

Because the encapsulation is real (no distinguishing marker at invocation
time), the *only* way to reconstruct "who actually ended up paying for
whom" after the fact is the `attempts` audit trail attached to each node's
own result: every attempt (`:direct`, `:phase`, or `:escalation`) is
recorded on the node whose demand it was trying to cover, even when the
custody or action doing the covering belongs to a different (ancestor)
node. An outside observer can walk the whole story via `attempts`; no
single node, while being resolved, ever could.

## Consequences

- Domain logic registered via `ActionRegistry` never needs to know whether
  the number it's being asked to cover is "genuinely" the node's own or
  partly inherited — which is exactly the point: from the perspective of
  whoever is being asked to act, that distinction is irrelevant to the
  action of covering it.
- The `demanded` / `own_demand` / `inherited_shortfall` split in a node's
  result exists purely for **observability** — it has no bearing on how
  resolution itself behaves, only on what a human or monitoring system can
  see afterward.
- A node's own `gap` is only knowable in full once its entire ancestor
  chain has finished processing (since a later, higher-level resolution
  can retroactively "pay off" an earlier shortfall). `resolve_tree`
  reflects this with a settlement pass after the main post-order walk;
  the resulting `gap` on any node is the final, ancestor-aware answer.
- This design intentionally does not support "explain why root's total
  changed" by pointing at one specific leaf — only the full attempts trail,
  read top to bottom, tells that story. This is a deliberate trade: a
  human reading a single node's result gets a clean, local answer; a human
  who needs the whole causal chain reads the audit trail instead.
