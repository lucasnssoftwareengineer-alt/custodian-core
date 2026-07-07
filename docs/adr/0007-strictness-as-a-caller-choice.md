# 7. Strictness as a caller choice

Date: 2026-07-07

## Status

Accepted

## Context

A `Custody` can be `currently_valid?` (its status isn't `broken`/`expired`,
and, for time-bound validity types, the current time falls within bounds)
while also being `at_risk` — a status that signals "this custodian may not
reliably follow through," without asserting that the custody is legally
void. `Custody#trustworthy?` already exists as
`currently_valid? && !at_risk?`, deliberately distinct from
`currently_valid?` alone, precisely because risk is a signal about the
future, not a statement about the present (see the amendment to step 3 of
this build plan, which introduced `at_risk?`/`trustworthy?`/`healthcheck`).

When `Adjuster.resolve_tree` walks the tree, it has to decide, for every
node, which custodies are even worth consulting. Not every caller wants the
same answer to that question: some resolutions genuinely only care whether
a custody is in force right now (e.g. a report that must reflect the
system's current legal state); others want to be conservative and skip
anything flagged risky, even if it's technically still valid (e.g. an
automated resolution run that actually moves things forward and shouldn't
lean on a custodian who might not show up).

## Decision

`resolve_tree` accepts a `strictness:` keyword (`:valid` by default, or
`:trustworthy`) that the caller chooses per invocation:

- `strictness: :valid` — consults any custody where `currently_valid?` is
  true. An `at_risk` custody is still tried; risk alone does not disqualify
  it.
- `strictness: :trustworthy` — consults only custodies where `trustworthy?`
  is true, which additionally excludes anything `at_risk`.

This is not a property of a `Custody` or a `Node` — it is a property of
*the resolution being performed*. The same tree, with the same custodies,
can legitimately be resolved once under `:valid` (e.g. for a status report)
and once under `:trustworthy` (e.g. for an automated action run) with
materially different results, and both are correct answers to two
different questions.

## Consequences

- Nothing about a `Custody`'s own data changes based on strictness — only
  which custodies the Adjuster is willing to consult. The distinction is
  entirely in the calling context, keeping `Custody` itself simple and
  reusable across both use cases.
- Satellite gems and host apps do not need to duplicate this filtering
  logic themselves; picking a strictness level is a one-keyword decision
  at the call site.
- Any future strictness level must be justified in these same terms: a
  distinct, caller-relevant answer to "which custodies count," not a new
  domain-specific concept (which would violate
  [ADR 0001](0001-domain-agnostic-core.md)).
