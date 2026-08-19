# custodian-core

The core has no business rules from any specific domain — it only knows how
to resolve a chain of custody: identify the next responsible party, and
demand from them the execution of the action the previous ward could not
fulfill, climbing the tree until someone has the capacity to act.

`custodian-core` is a Ruby (Rails engine) gem that implements this
resolution mechanism over a tree of `Node` records. It ships no domain
vocabulary — no money, no storage, no networking — only the shape of
responsibility and the machinery to walk it. Concrete domains plug in as
satellite gems.

> ⚠️ **Early-stage (0.1.0).** The API may still change and this gem has not
> yet been battle-tested in production. It is provided "as is", without
> warranty of any kind (see [License](#license)). Use at your own risk.

## Vocabulary

- **Node** — something that needs to be resolved: the **ward**. Nodes form
  a tree (via [ancestry](https://github.com/stefankroes/ancestry)); a node's
  demand is either binary ("this must be done") or numeric (a quantity to
  cover).
- **Custody** — the agreement between a **custodian** (whoever takes on
  responsibility for a ward) and the ward itself: which action to call, at
  what priority, and under what validity window.
- **custodian** — the party who took on a `Custody`. It can be anything
  polymorphic — including another `Node`.
- **Adjuster** — walks the tree and resolves it, invoking custodies through
  the `ActionRegistry` and escalating what nobody could cover. Named after
  the insurance claims adjuster: someone who reviews a policy, evaluates
  what happened, and decides who's responsible for covering it.
- **ActionRegistry** — the plug-in point. Host apps and satellite gems
  register named actions here; the core never knows what an action
  actually does.

## Quick start

```ruby
root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
child = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 50, parent: root)

Custodian::Core::Custody.create!(ward: root, action_name: "cover_shortfall")

Custodian::Core::ActionRegistry.register(:cover_shortfall) do |node, custody, remaining|
  remaining # fully resolves whatever it's asked to cover
end

result = Custodian::Core::Adjuster.resolve_tree(root)

result[child.id][:gap]   #=> 0.0 (BigDecimal) - resolved via escalation into root
result[root.id][:gap]    #=> 0.0 - root's own 100 + child's inherited 50 = 150, fully covered
result[root.id][:attempts]
#=> [{ custody_id: 1, action_name: "cover_shortfall", outcome: 0.15e3, via: :direct }]
```

`resolve_tree` returns a Hash keyed by node id. Each entry reports what was
`demanded`, how much of it is `own_demand` vs `inherited_shortfall`, the
`resolved_amount` and remaining `gap`, binary-specific fields, and a full
`attempts` audit trail (`via: :direct | :phase | :escalation`) for
reconstructing the whole story after the fact.

## The outcome contract

A registered action receives `(node, custody, remaining)` and must return:

- `:resolved` — fully satisfied, stop trying custodies for this node
- `:failed` — this custodian couldn't act, try the next one
- a non-negative `Numeric` — partial resolution, **in the same unit as the
  node's `demand_value`** (see
  [ADR 0004](docs/adr/0004-numeric-outcome-unit-commensurability.md); the
  core cannot enforce unit correctness, only that the number itself is
  well-formed)

Anything else — `true`, `nil`, a `String`, a negative number — raises
`ActionRegistry::InvalidOutcomeError` immediately. See
[ADR 0008](docs/adr/0008-registry-defensiveness.md) for why this is
deliberately strict rather than forgiving.

## Security: action registration is a trust boundary

Registered actions and phase handlers are ordinary Ruby blocks that
`custodian-core` executes with your application's full privileges. The core
validates only the *shape* of what an action returns — it does **not**
sandbox what an action does. Treat registration as privileged
configuration:

- Register actions only from code you control (your app, or satellite gems
  you trust). Never build or register an action from untrusted input.
- Never derive an `action_name` to invoke, or an action's body, from
  user-supplied data without validating it against a fixed allowlist of
  known actions.
- `action_params` on a `Custody` is passed to the action as-is; validate
  and authorize any host-exposed path that lets an end user set
  `action_name`, `action_params`, or custody attributes, since those
  determine what code runs and on whose behalf.

## Resolution order and encapsulation

For each node, post-order (children before parents), the Adjuster tries, in
order: **direct custodies** (by `priority_weight`, then id), then
**registered phases** (an extension point, e.g. for a future
sibling-generosity satellite), then **escalation**.

Escalation is the gem's most distinctive idea: if a node still can't cover
its demand after the two steps above, that shortfall is folded into its
direct parent's own demand before the parent is even processed — with no
marker distinguishing "my own demand" from "what my child couldn't cover."
The parent's custodians never know a child failed; they just see a bigger
number. This means **a grandparent never sees a grandchild** — each level
only ever perceives one level down, exactly like a real management chain.
The full story (who ultimately paid for whom) is only reconstructable from
the `attempts` audit trail, not from any single node's own view. See
[ADR 0006](docs/adr/0006-escalation-with-per-level-encapsulation.md).

Binary nodes are a **magnitude firewall**: a numeric node's demand never
aggregates through a binary ancestor, even though escalation still walks
*into* one if it's the direct parent — aggregation and escalation are
different mechanisms. See
[ADR 0005](docs/adr/0005-binary-nodes-as-magnitude-firewalls.md).

## Strictness: `:valid` vs `:trustworthy`

`resolve_tree(root, strictness: :valid)` (the default) consults any custody
that is currently legally valid, regardless of risk signals.
`strictness: :trustworthy` additionally excludes custodies flagged
`at_risk` — for callers who care not just "is this custody in force" but
"do I actually trust it right now." See
[ADR 0007](docs/adr/0007-strictness-as-a-caller-choice.md).

## This is domain-agnostic — satellite gems bring the meaning

`custodian-core` never mentions money, storage, or networking. Examples of
what a satellite gem could layer on top, none of which live here:

- **Finance**: a `custodian-payments` gem registering `:charge_card` or
  `:draw_from_reserve` actions, where a Node's numeric demand is an amount
  owed and escalation models who is ultimately liable for a shortfall.
- **Storage failover**: a `custodian-storage` gem registering
  `:replicate_to_backup`, where a binary Node represents "this object must
  be durably stored somewhere" and custody escalates through a chain of
  storage backends.
- **Network routing**: a `custodian-routing` gem registering
  `:forward_via_peer`, where demand is bandwidth to place and unresolved
  capacity escalates to an upstream peer.

## Satellites (not yet built)

Planned extensions that do not exist in this gem yet:

- **Sibling generosity / "brotherhood"** — a phase (via `register_phase`)
  that lets a resolved sibling's surplus cover another sibling's shortfall
  before escalating to the parent.
- **Resource pools** — shared capacity a custodian can draw from across
  multiple wards, instead of resolving each in isolation.
- **Execution history / honor tracking** — a record of how reliably a
  custodian has actually resolved what it took on, feeding back into future
  eligibility decisions.

## Installation

### Compatibility

`custodian-core` 0.1 supports Ruby 3.2 or newer, Rails 7.x and 8.x, and
`ancestry` 4.x and 5.x. The lower Ruby bound keeps the supported runtime
aligned with the CI matrix and with the currently supported Rails majors.

Add the gem to your host Rails application's Gemfile:

```ruby
gem "custodian-core", "~> 0.1.1"
```

Then install it:

```sh
bundle install
```

Then install the engine's migrations:

```sh
bundle exec rails custodian_core:install:migrations
bundle exec rails db:migrate
```

## Running tests

```sh
bundle exec rake       # runs both rspec and rubocop
bundle exec rspec      # specs only
bundle exec rubocop    # lint only
```

## Architecture decisions

See [docs/adr](docs/adr/0000-index.md) for the full record of design
decisions and their rationale.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
