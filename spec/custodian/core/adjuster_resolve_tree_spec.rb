# frozen_string_literal: true

RSpec.describe Custodian::Core::Adjuster do
  describe ".resolve_tree" do
    around do |example|
      Custodian::Core::ActionRegistry.clear!
      described_class.clear_phases!
      example.run
      Custodian::Core::ActionRegistry.clear!
      described_class.clear_phases!
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

      expect(result[node.id][:attempts].pluck(:custody_id)).to eq([older.id, newer.id])
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
      expect(result[node.id][:attempts].pluck(:outcome)).to eq([60, 40])
    end

    it "rejects an outcome larger than remaining instead of producing a negative gap" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      Custodian::Core::Custody.create!(ward: node, action_name: "overpay")
      Custodian::Core::ActionRegistry.register(:overpay) { |_n, _c, _remaining| 101 }

      expect { described_class.resolve_tree(node) }
        .to raise_error(Custodian::Core::ActionRegistry::InvalidOutcomeError, /exceeding remaining demand/)
    end

    it "rejects persisted negative demand that bypassed model validation" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      node.update_column(:demand_value, -1) # rubocop:disable Rails/SkipsModelValidations -- deliberate corruption

      expect { described_class.resolve_tree(node.reload) }
        .to raise_error(ArgumentError, /total demand must be non-negative/)
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

    it "accepts exactly the supported strictness symbols" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 0)

      expect { described_class.resolve_tree(node, strictness: :valid) }.not_to raise_error
      expect { described_class.resolve_tree(node, strictness: :trustworthy) }.not_to raise_error
    end

    it "rejects unsupported strictness values immediately" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 0)

      [:unknown, "valid", nil].each do |strictness|
        expect { described_class.resolve_tree(node, strictness: strictness) }
          .to raise_error(ArgumentError, /unsupported strictness #{Regexp.escape(strictness.inspect)}/)
      end
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

    context "when a numeric child's unresolved shortfall escalates into its parent's total_demand" do
      let!(:parent) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 50) }
      let!(:child) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100, parent: parent) }
      let!(:custody) { Custodian::Core::Custody.create!(ward: parent, action_name: "pay") }
      let(:received_args) { [] }

      before do
        args = received_args
        Custodian::Core::ActionRegistry.register(:pay) do |n, c, remaining|
          args.replace([n, c, remaining])
          :resolved
        end
      end

      it "shows the parent's demanded/own/inherited split, with the child resolved via escalation",
         :aggregate_failures do
        result = described_class.resolve_tree(parent)

        expect(result[parent.id][:demanded]).to eq(BigDecimal("150"))
        expect(result[parent.id][:own_demand]).to eq(BigDecimal("50"))
        expect(result[parent.id][:inherited_shortfall]).to eq(BigDecimal("100"))
        expect(result[parent.id][:gap]).to eq(BigDecimal("0"))
        expect(result[child.id][:gap]).to eq(BigDecimal("0"))
        expect(result[child.id][:attempts]).to eq(
          [{ custody_id: nil, action_name: nil, outcome: :resolved, via: :escalation }]
        )
      end

      it "invokes the action with ONE combined remaining figure, no own/inherited distinction" do
        described_class.resolve_tree(parent)

        expect(received_args).to eq([parent, custody, BigDecimal("150")])
      end
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

    context "when the middle node resolves everything in a 3-level tree" do
      let!(:root) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10) }
      let!(:middle) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 20, parent: root) }
      let!(:leaf) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 30, parent: middle) }
      let!(:root_custody) { Custodian::Core::Custody.create!(ward: root, action_name: "root_pay") }
      let!(:middle_custody) { Custodian::Core::Custody.create!(ward: middle, action_name: "middle_pay") }

      before do
        Custodian::Core::ActionRegistry.register(:root_pay) { |_n, _c, _remaining| :resolved }
        Custodian::Core::ActionRegistry.register(:middle_pay) { |_n, _c, _remaining| :resolved }
      end

      it "resolves the leaf (via escalation) and the middle (own + inherited)", :aggregate_failures do
        result = described_class.resolve_tree(root)

        expect(result[leaf.id][:gap]).to eq(BigDecimal("0"))
        expect(result[middle.id][:demanded]).to eq(BigDecimal("50"))
        expect(result[middle.id][:gap]).to eq(BigDecimal("0"))
      end

      it "keeps the grandparent unaware of the grandchild: inherited_shortfall 0, no leaf/middle reference",
         :aggregate_failures do
        result = described_class.resolve_tree(root)

        expect(result[root.id][:inherited_shortfall]).to eq(BigDecimal("0"))
        expect(result[root.id][:demanded]).to eq(BigDecimal("10"))
        expect(result[root.id][:attempts]).to eq(
          [{ custody_id: root_custody.id, action_name: "root_pay", outcome: :resolved, via: :direct }]
        )
        expect(result[root.id][:attempts].none? { |a| a[:custody_id] == middle_custody.id }).to be true
      end
    end

    context "when no custody anywhere resolves anything" do
      let!(:root) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10) }
      let!(:child) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 20, parent: root) }
      let!(:root_custody) { Custodian::Core::Custody.create!(ward: root, action_name: "try_root") }
      let!(:child_custody) { Custodian::Core::Custody.create!(ward: child, action_name: "try_child") }

      before do
        Custodian::Core::ActionRegistry.register(:try_root) { |_n, _c, _remaining| :failed }
        Custodian::Core::ActionRegistry.register(:try_child) { |_n, _c, _remaining| :failed }
      end

      it "records the child's failed direct attempt plus a failed escalation attempt", :aggregate_failures do
        result = described_class.resolve_tree(root)

        expect(result[child.id][:gap]).to eq(BigDecimal("20"))
        expect(result[child.id][:attempts]).to eq(
          [
            { custody_id: child_custody.id, action_name: "try_child", outcome: :failed, via: :direct },
            { custody_id: nil, action_name: nil, outcome: :failed, via: :escalation }
          ]
        )
      end

      it "reports the final unresolved gap at the root" do
        result = described_class.resolve_tree(root)

        expect(result[root.id][:demanded]).to eq(BigDecimal("30"))
        expect(result[root.id][:gap]).to eq(BigDecimal("30"))
        expect(result[root.id][:attempts]).to eq(
          [{ custody_id: root_custody.id, action_name: "try_root", outcome: :failed, via: :direct }]
        )
      end
    end

    it "runs a registered phase between direct custodies and escalation, recording it as via: :phase",
       :aggregate_failures do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100)
      received_args = nil
      described_class.register_phase(:sibling_generosity, lambda do |n, remaining, context|
        received_args = [n, remaining, context]
        :resolved
      end)

      result = described_class.resolve_tree(node)

      expect(result[node.id][:gap]).to eq(BigDecimal("0"))
      expect(result[node.id][:attempts]).to eq(
        [{ custody_id: nil, action_name: :sibling_generosity, outcome: :resolved, via: :phase }]
      )
      expect(received_args[0]).to eq(node)
      expect(received_args[1]).to eq(BigDecimal("100"))
      expect(received_args[2].keys).to contain_exactly(:siblings, :aggregation, :strictness)
      expect(received_args[2][:strictness]).to eq(:valid)
    end

    it "uses one phase snapshot for a resolution while phases are changed concurrently" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)
      phase_started, phase_registered = Array.new(2) { Queue.new }
      described_class.register_phase(:initial, lambda do |_node, _remaining, _context|
        phase_started << true
        phase_registered.pop
        :failed
      end)
      mutator = Thread.new do
        phase_started.pop
        described_class.register_phase(:late, ->(_node, _remaining, _context) { :failed })
        phase_registered << true
      end

      result = described_class.resolve_tree(node)
      mutator.join

      expect(result[node.id][:attempts].pluck(:action_name)).to eq([:initial])
    end

    it "does not corrupt phase state under concurrent registrations" do
      node = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)
      names = 20.times.map { |index| :"phase_#{index}" }
      threads = names.map do |name|
        Thread.new { described_class.register_phase(name, ->(_node, _remaining, _context) { :failed }) }
      end
      threads.each(&:join)

      attempted_names = described_class.resolve_tree(node)[node.id][:attempts].pluck(:action_name)

      expect(attempted_names).to match_array(names)
    end

    it "mutates nothing: updated_at is untouched across all records", :aggregate_failures do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 50)
      child = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 100, parent: root)
      custody = Custodian::Core::Custody.create!(ward: root, action_name: "pay")
      Custodian::Core::ActionRegistry.register(:pay) { |_n, _c, _remaining| :resolved }
      root_updated_at = root.reload.updated_at
      child_updated_at = child.reload.updated_at
      custody_updated_at = custody.reload.updated_at

      described_class.resolve_tree(root)

      expect(root.reload.updated_at).to eq(root_updated_at)
      expect(child.reload.updated_at).to eq(child_updated_at)
      expect(custody.reload.updated_at).to eq(custody_updated_at)
    end
  end
end
