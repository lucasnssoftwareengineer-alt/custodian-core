# frozen_string_literal: true

RSpec.describe Custodian::Core::Adjuster do
  describe ".resolve_tree" do
    around do |example|
      Custodian::Core::ActionRegistry.clear!
      Custodian::Core::Adjuster.clear_phases!
      example.run
      Custodian::Core::ActionRegistry.clear!
      Custodian::Core::Adjuster.clear_phases!
    end

    it "resolves a single numeric node with one custody that returns :resolved" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      custody = Custodian::Core::Custody.create!(ward: node, action_name: "pay")
      Custodian::Core::ActionRegistry.register(:pay) { |_n, _c, _remaining| :resolved }

      result = described_class.resolve_tree(node)

      expect(result[node.id][:gap]).to eq(BigDecimal("0"))
      expect(result[node.id][:attempts]).to eq(
        [{ custody_id: custody.id, action_name: "pay", outcome: :resolved, via: :direct }]
      )
    end

    it "tries custodies in priority_weight ascending order (lower weight first)" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      second = Custodian::Core::Custody.create!(ward: node, action_name: "second_try", priority_weight: 10)
      first = Custodian::Core::Custody.create!(ward: node, action_name: "first_try", priority_weight: 1)
      Custodian::Core::ActionRegistry.register(:first_try) { |_n, _c, _remaining| :failed }
      Custodian::Core::ActionRegistry.register(:second_try) { |_n, _c, _remaining| :resolved }

      result = described_class.resolve_tree(node)

      expect(result[node.id][:attempts]).to eq(
        [
          { custody_id: first.id, action_name: "first_try", outcome: :failed, via: :direct },
          { custody_id: second.id, action_name: "second_try", outcome: :resolved, via: :direct }
        ]
      )
    end

    it "breaks a priority_weight tie by ascending custody id" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      older = Custodian::Core::Custody.create!(ward: node, action_name: "older", priority_weight: 5)
      newer = Custodian::Core::Custody.create!(ward: node, action_name: "newer", priority_weight: 5)
      expect(older.id).to be < newer.id
      Custodian::Core::ActionRegistry.register(:older) { |_n, _c, _remaining| :failed }
      Custodian::Core::ActionRegistry.register(:newer) { |_n, _c, _remaining| :resolved }

      result = described_class.resolve_tree(node)

      expect(result[node.id][:attempts].map { |a| a[:custody_id] }).to eq([older.id, newer.id])
    end

    it "accumulates partial Numeric outcomes from multiple custodies until fully resolved" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      Custodian::Core::Custody.create!(ward: node, action_name: "pay_a", priority_weight: 1)
      Custodian::Core::Custody.create!(ward: node, action_name: "pay_b", priority_weight: 2)
      Custodian::Core::ActionRegistry.register(:pay_a) { |_n, _c, remaining| [remaining, 60].min }
      Custodian::Core::ActionRegistry.register(:pay_b) { |_n, _c, remaining| remaining }

      result = described_class.resolve_tree(node)

      expect(result[node.id][:gap]).to eq(BigDecimal("0"))
      expect(result[node.id][:resolved_amount]).to eq(BigDecimal("100"))
      expect(result[node.id][:attempts].map { |a| a[:outcome] }).to eq([60, 40])
    end

    it "consults an at_risk custody under :valid but skips it under :trustworthy" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      custody = Custodian::Core::Custody.create!(ward: node, action_name: "pay", status: "at_risk")
      Custodian::Core::ActionRegistry.register(:pay) { |_n, _c, _remaining| :resolved }

      valid_result = described_class.resolve_tree(node, strictness: :valid)
      expect(valid_result[node.id][:attempts]).to eq(
        [{ custody_id: custody.id, action_name: "pay", outcome: :resolved, via: :direct }]
      )

      trustworthy_result = described_class.resolve_tree(node, strictness: :trustworthy)
      expect(trustworthy_result[node.id][:attempts]).to eq([])
      expect(trustworthy_result[node.id][:gap]).to eq(BigDecimal("100"))
    end

    it "does not consult a custody that does not apply_to? the node (e.g. repudiated)" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      custody = Custodian::Core::Custody.create!(ward: node, action_name: "pay")
      Custodian::Core::CustodyRepudiatedNode.create!(custody: custody, node: node)
      Custodian::Core::ActionRegistry.register(:pay) { |_n, _c, _remaining| :resolved }

      result = described_class.resolve_tree(node)

      expect(result[node.id][:attempts]).to eq([])
      expect(result[node.id][:gap]).to eq(BigDecimal("100"))
    end

    it "escalates a numeric child's unresolved shortfall into its parent's total_demand", :aggregate_failures do
      parent = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 50)
      child = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100, parent: parent)
      custody = Custodian::Core::Custody.create!(ward: parent, action_name: "pay")
      received_args = nil
      Custodian::Core::ActionRegistry.register(:pay) do |n, c, remaining|
        received_args = [n, c, remaining]
        :resolved
      end

      result = described_class.resolve_tree(parent)

      expect(result[parent.id][:demanded]).to eq(BigDecimal("150"))
      expect(result[parent.id][:own_demand]).to eq(BigDecimal("50"))
      expect(result[parent.id][:inherited_shortfall]).to eq(BigDecimal("100"))
      expect(result[parent.id][:gap]).to eq(BigDecimal("0"))

      expect(result[child.id][:gap]).to eq(BigDecimal("0"))
      expect(result[child.id][:attempts]).to eq(
        [{ custody_id: nil, action_name: nil, outcome: :resolved, via: :escalation }]
      )

      # Locks in the encapsulation design: the action sees ONE combined
      # remaining figure, with no marker distinguishing own from inherited.
      expect(received_args).to eq([parent, custody, BigDecimal("150")])
    end

    it "escalates an unresolved binary child, invoking the parent's custody on the child's behalf" do
      parent = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 0)
      child = Custodian::Core::Node.create!(demand_type: "binary", parent: parent)
      custody = Custodian::Core::Custody.create!(ward: parent, action_name: "approve")
      received_args = nil
      Custodian::Core::ActionRegistry.register(:approve) do |n, c, remaining|
        received_args = [n, c, remaining]
        :resolved
      end

      result = described_class.resolve_tree(parent)

      expect(received_args).to eq([child, custody, nil])
      expect(result[child.id][:binary_resolved]).to be true
      expect(result[parent.id][:pending_binaries_escalated]).to eq([child.id])
    end

    it "keeps the grandparent unaware of the grandchild once the middle node resolves everything",
       :aggregate_failures do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)
      middle = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 20, parent: root)
      leaf = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 30, parent: middle)
      root_custody = Custodian::Core::Custody.create!(ward: root, action_name: "root_pay")
      middle_custody = Custodian::Core::Custody.create!(ward: middle, action_name: "middle_pay")
      Custodian::Core::ActionRegistry.register(:root_pay) { |_n, _c, _remaining| :resolved }
      Custodian::Core::ActionRegistry.register(:middle_pay) { |_n, _c, _remaining| :resolved }

      result = described_class.resolve_tree(root)

      expect(result[leaf.id][:gap]).to eq(BigDecimal("0"))
      expect(result[middle.id][:demanded]).to eq(BigDecimal("50"))
      expect(result[middle.id][:gap]).to eq(BigDecimal("0"))

      expect(result[root.id][:inherited_shortfall]).to eq(BigDecimal("0"))
      expect(result[root.id][:demanded]).to eq(BigDecimal("10"))
      expect(result[root.id][:attempts]).to eq(
        [{ custody_id: root_custody.id, action_name: "root_pay", outcome: :resolved, via: :direct }]
      )
      expect(result[root.id][:attempts].none? { |a| a[:custody_id] == middle_custody.id }).to be true
    end
  end
end
