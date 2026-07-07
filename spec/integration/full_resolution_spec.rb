# frozen_string_literal: true

# Full end-to-end integration scenario, exercising Node, Custody,
# CustodyNodeRule/CustodyRepudiatedNode (via Custody#applies_to?),
# ActionRegistry, and Adjuster.resolve_tree together in one realistic tree.
#
# KNOWN GAP surfaced while writing this spec (not fixed here, per this
# step's own instructions - reported back instead of silently patched):
# when a numeric node (audit_fees) escalates its shortfall into a BINARY
# parent (certification), Adjuster folds it into the binary parent's own
# numeric pool - a deliberate step-7 design choice for that edge case. But
# the result schema forces `gap`/`demanded` to nil for any binary node, so
# whether that absorbed pool actually resolved is invisible in the
# structured result (only visible via the raw `attempts` array). Worse,
# `escalate_numeric_shortfall` refuses to propagate ANYTHING past a binary
# node, and `ancestor_resolved?` skips binary ancestors when walking up -
# so if certification's pool were NOT fully covered by a custody of its
# own, that shortfall would be silently discarded (never reaching
# logistics/root), yet audit_fees could still end up reporting gap: 0
# "resolved via escalation" purely because root happens to resolve its
# own, unrelated demand further up the chain. In THIS scenario
# certification's pool genuinely IS fully covered locally (custody C2b
# below), so the numbers asserted here are correct - but the mechanism
# that concludes "resolved" would not reliably distinguish a real local
# resolution from an unrelated root-level coincidence. Left for a future
# step to address deliberately with its own TDD cycle, not smuggled in here.
RSpec.describe "full tree resolution", :aggregate_failures do
  around do |example|
    Custodian::Core::ActionRegistry.clear!
    Custodian::Core::Adjuster.clear_phases!
    example.run
    Custodian::Core::ActionRegistry.clear!
    Custodian::Core::Adjuster.clear_phases!
  end

  # ------------------------------------------------------------------
  # Tree
  #
  #   operations (numeric, 1000)
  #   +-- logistics (numeric, 500)
  #   |    +-- fleet_fuel (numeric, 300)
  #   |    +-- certification (BINARY)
  #   |         +-- audit_fees (numeric, 200) - firewalled from aggregation
  #   +-- production (numeric, 400)
  #        +-- raw_materials (numeric, 600)
  #        +-- maintenance (numeric, 150)
  # ------------------------------------------------------------------

  let!(:operations) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 1000) }
  let!(:logistics) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 500, parent: operations) }
  let!(:fleet_fuel) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 300, parent: logistics) }
  let!(:certification) { Custodian::Core::Node.create!(demand_type: "binary", parent: logistics) }
  let!(:audit_fees) do
    Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 200, parent: certification)
  end
  let!(:production) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 400, parent: operations) }
  let!(:raw_materials) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 600, parent: production) }
  let!(:maintenance) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 150, parent: production) }

  # ------------------------------------------------------------------
  # Custodies
  #
  # logistics gets its own custody (C_log): the original scenario never
  # assigned logistics a custody despite it carrying its own 500 demand,
  # which would have left an extra, unaccounted-for 500 shortfall
  # reaching root and thrown off every downstream "demanded" figure.
  # Added here deliberately, not a silent fix - see conversation.
  # ------------------------------------------------------------------

  let!(:c_log) { Custodian::Core::Custody.create!(ward: logistics, action_name: "cover_logistics") }
  let!(:c_fuel) { Custodian::Core::Custody.create!(ward: fleet_fuel, action_name: "pay_fuel", priority_weight: 1) }
  let!(:c_certify) { Custodian::Core::Custody.create!(ward: certification, action_name: "certify") }
  let!(:c_pay_audit) do
    Custodian::Core::Custody.create!(ward: certification, action_name: "pay_audit", priority_weight: 2)
  end
  let!(:c_buy_cheap) do
    Custodian::Core::Custody.create!(
      ward: raw_materials, action_name: "buy_cheap", priority_weight: 1, status: "at_risk"
    )
  end
  let!(:c_buy_market) { Custodian::Core::Custody.create!(ward: raw_materials, action_name: "buy_market", priority_weight: 2) }
  let!(:c_cover_production) { Custodian::Core::Custody.create!(ward: production, action_name: "cover_production") }
  let!(:c_emergency_fund) { Custodian::Core::Custody.create!(ward: operations, action_name: "emergency_fund") }

  let(:phase_log) { [] }
  let(:run) { {} }

  before do
    Custodian::Core::ActionRegistry.register(:cover_logistics) { |_n, _c, remaining| remaining }
    Custodian::Core::ActionRegistry.register(:pay_fuel) { |_n, _c, remaining| remaining }
    # :certify only answers the binary yes/no ask (remaining nil); it
    # declines any numeric ask so it doesn't accidentally "resolve" the
    # inherited audit_fees pool just by always returning :resolved.
    Custodian::Core::ActionRegistry.register(:certify) { |_n, _c, remaining| remaining.nil? ? :resolved : :failed }
    # :pay_audit is the inverse: declines binary asks, fully covers numeric ones.
    Custodian::Core::ActionRegistry.register(:pay_audit) { |_n, _c, remaining| remaining.nil? ? :failed : remaining }
    Custodian::Core::ActionRegistry.register(:buy_cheap) { |_n, _c, remaining| remaining }
    Custodian::Core::ActionRegistry.register(:buy_market) { |_n, _c, _remaining| 400 }
    Custodian::Core::ActionRegistry.register(:cover_production) { |_n, _c, _remaining| 150 }
    Custodian::Core::ActionRegistry.register(:emergency_fund) { |_n, _c, remaining| remaining }

    Custodian::Core::Adjuster.register_phase(:observer, lambda do |node, _remaining, _context|
      phase_log << node.id
      :failed
    end)
  end

  def resolve!(strictness)
    run[:query_count] = count_queries do
      run[:result] = Custodian::Core::Adjuster.resolve_tree(operations, strictness: strictness)
    end
    run[:result]
  end

  def result
    run[:result]
  end

  def query_count
    run[:query_count]
  end

  def all_records
    [
      operations, logistics, fleet_fuel, certification, audit_fees, production, raw_materials, maintenance,
      c_log, c_fuel, c_certify, c_pay_audit, c_buy_cheap, c_buy_market, c_cover_production, c_emergency_fund
    ]
  end

  describe "strictness: :trustworthy (C3 is at_risk, so it is skipped)" do
    before { resolve!(:trustworthy) }

    it "fully resolves fleet_fuel directly via C1" do
      expect(result[fleet_fuel.id][:gap]).to eq(BigDecimal("0"))
      expect(result[fleet_fuel.id][:resolved_amount]).to eq(BigDecimal("300"))
      expect(result[fleet_fuel.id][:attempts]).to eq(
        [{ custody_id: c_fuel.id, action_name: "pay_fuel", outcome: BigDecimal("300"), via: :direct }]
      )
    end

    it "resolves audit_fees via escalation into certification's C2b" do
      expect(result[audit_fees.id][:gap]).to eq(BigDecimal("0"))
      expect(result[audit_fees.id][:attempts].last).to eq(
        { custody_id: nil, action_name: nil, outcome: :resolved, via: :escalation }
      )
    end

    it "resolves certification's own binary ask via C2, and its inherited numeric pool via C2b" do
      expect(result[certification.id][:binary]).to be true
      expect(result[certification.id][:binary_resolved]).to be true
      expect(result[certification.id][:inherited_shortfall]).to eq(BigDecimal("200"))
      expect(result[certification.id][:attempts]).to eq(
        [
          { custody_id: c_certify.id, action_name: "certify", outcome: :resolved, via: :direct },
          { custody_id: c_certify.id, action_name: "certify", outcome: :failed, via: :direct },
          { custody_id: c_pay_audit.id, action_name: "pay_audit", outcome: BigDecimal("200"), via: :direct }
        ]
      )
    end

    it "proves aggregation and escalation are different mechanisms: the firewall blocks aggregation " \
       "(logistics' aggregated_demand is 500 + fleet_fuel's 300 = 800, NEVER 300 + audit_fees' 200 " \
       "tunneling through the binary certification node), but escalation still walked audit_fees' " \
       "shortfall one level up into certification, its direct binary parent" do
      aggregation = Custodian::Core::Adjuster.aggregate_demand(operations)
      expect(aggregation[logistics.id][:aggregated_demand]).to eq(BigDecimal("800"))
      expect(result[certification.id][:inherited_shortfall]).to eq(BigDecimal("200"))
    end

    it "does not consult C3 at all under :trustworthy, since it is at_risk" do
      expect(result[raw_materials.id][:attempts].pluck(:custody_id)).not_to include(c_buy_cheap.id)
    end

    it "leaves a 200 shortfall from raw_materials (C4 covers only 400 of 600), later settled once " \
       "production and root resolve everything above it" do
      expect(result[raw_materials.id][:attempts]).to eq(
        [
          { custody_id: c_buy_market.id, action_name: "buy_market", outcome: 400, via: :direct },
          { custody_id: nil, action_name: :observer, outcome: :failed, via: :phase },
          { custody_id: nil, action_name: nil, outcome: :resolved, via: :escalation }
        ]
      )
    end

    it "combines production's own demand with maintenance and raw_materials shortfalls (400+150+200=750)" do
      expect(result[production.id][:demanded]).to eq(BigDecimal("750"))
      expect(result[production.id][:resolved_amount]).to eq(BigDecimal("150"))
      expect(result[production.id][:gap]).to eq(BigDecimal("0")) # settled: root eventually covers it
    end

    it "shows root's demanded as own (1000) + inherited from production only (600), fully resolved by C6" do
      expect(result[operations.id][:demanded]).to eq(BigDecimal("1600"))
      expect(result[operations.id][:gap]).to eq(BigDecimal("0"))
      expect(result[operations.id][:attempts]).to eq(
        [{ custody_id: c_emergency_fund.id, action_name: "emergency_fund", outcome: BigDecimal("1600"), via: :direct }]
      )
    end

    it "keeps root's attempts free of any reference to grandchildren's custodies" do
      root_custody_ids = result[operations.id][:attempts].pluck(:custody_id)
      expect(root_custody_ids).to eq([c_emergency_fund.id])
      expect(root_custody_ids).not_to include(c_fuel.id, c_buy_cheap.id, c_buy_market.id, c_cover_production.id,
                                              c_certify.id, c_pay_audit.id, c_log.id)
    end

    it "runs the observer phase, in post-order, only for nodes not already resolved by direct custodies" do
      expect(phase_log).to eq([audit_fees.id, raw_materials.id, maintenance.id, production.id])
    end

    it "mutates no records" do
      timestamps_before = all_records.map { |record| [record.class, record.id, record.reload.updated_at] }

      resolve!(:trustworthy)

      timestamps_after = timestamps_before.map { |klass, id, _| [klass, id, klass.find(id).updated_at] }
      expect(timestamps_after).to eq(timestamps_before)
    end

    # NOTE: this is bounded by node/custody count (~21 queries measured for
    # this 8-node, 9-custody tree), not the O(1) ceiling aggregate_demand
    # achieves - Custody#applies_to? issues 2 queries per call and gets
    # called once per custody-eligibility check (up to twice for the binary
    # node, once for its own binary resolution and once for its numeric
    # pool). It does not explode with tree size, but it isn't optimal
    # either; a bulk-preload of repudiations/rules could bring this down to
    # a handful of queries total. Flagged for a future optimization pass,
    # not addressed here.
    it "keeps the total query count bounded by node/custody count, not scaling further with tree size" do
      expect(query_count).to be <= 30
    end
  end

  describe "strictness: :valid (C3 is now eligible, despite being at_risk)" do
    before { resolve!(:valid) }

    it "tries C3 first (priority 1) and fully resolves raw_materials without ever needing C4" do
      expect(result[raw_materials.id][:attempts]).to eq(
        [{ custody_id: c_buy_cheap.id, action_name: "buy_cheap", outcome: BigDecimal("600"), via: :direct }]
      )
      expect(result[raw_materials.id][:gap]).to eq(BigDecimal("0"))
    end

    it "combines production's own demand with only maintenance's shortfall (400+150=550)" do
      expect(result[production.id][:demanded]).to eq(BigDecimal("550"))
      expect(result[production.id][:resolved_amount]).to eq(BigDecimal("150"))
      expect(result[production.id][:gap]).to eq(BigDecimal("0"))
    end

    it "shows root's demanded as own (1000) + inherited from production only (400), fully resolved by C6" do
      expect(result[operations.id][:demanded]).to eq(BigDecimal("1400"))
      expect(result[operations.id][:gap]).to eq(BigDecimal("0"))
    end

    it "never invokes the observer phase for raw_materials this time (C3 alone fully resolves it)" do
      expect(phase_log).to eq([audit_fees.id, maintenance.id, production.id])
    end

    it "mutates no records" do
      timestamps_before = all_records.map { |record| [record.class, record.id, record.reload.updated_at] }

      resolve!(:valid)

      timestamps_after = timestamps_before.map { |klass, id, _| [klass, id, klass.find(id).updated_at] }
      expect(timestamps_after).to eq(timestamps_before)
    end

    # See the same note in the :trustworthy block above.
    it "keeps the total query count bounded by node/custody count, not scaling further with tree size" do
      expect(query_count).to be <= 30
    end
  end

  describe "the difference between the two strictness runs" do
    it "resolves raw_materials entirely differently: C4-partial-then-escalate under :trustworthy, " \
       "vs C3-alone-and-done under :valid - same tree, one status flag, materially different flow" do
      trustworthy_result = resolve!(:trustworthy)
      valid_result = resolve!(:valid)

      trustworthy_custody_ids = trustworthy_result[raw_materials.id][:attempts].filter_map { |a| a[:custody_id] }
      valid_custody_ids = valid_result[raw_materials.id][:attempts].filter_map { |a| a[:custody_id] }
      expect(trustworthy_custody_ids).to eq([c_buy_market.id])
      expect(valid_custody_ids).to eq([c_buy_cheap.id])

      expect(trustworthy_result[operations.id][:demanded]).to eq(BigDecimal("1600"))
      expect(valid_result[operations.id][:demanded]).to eq(BigDecimal("1400"))
    end
  end
end
