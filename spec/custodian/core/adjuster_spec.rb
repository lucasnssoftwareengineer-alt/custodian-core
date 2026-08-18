# frozen_string_literal: true

RSpec.describe Custodian::Core::Adjuster do
  describe ".aggregate_demand" do
    it "returns aggregated_demand equal to own_demand for a single numeric node with no children" do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)

      result = described_class.aggregate_demand(root)

      expect(result[root.id][:own_demand]).to eq(BigDecimal("10"))
      expect(result[root.id][:aggregated_demand]).to eq(BigDecimal("10"))
    end

    it "aggregates the sum of two numeric children into the numeric root" do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)
      Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 5, parent: root)
      Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 7, parent: root)

      result = described_class.aggregate_demand(root)

      expect(result[root.id][:aggregated_demand]).to eq(BigDecimal("22"))
    end

    it "aggregates a three-level numeric tree post-order (middle level before root)" do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 1)
      middle = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 2, parent: root)
      Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 3, parent: middle)
      Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 4, parent: middle)

      result = described_class.aggregate_demand(root)

      expect(result[middle.id][:aggregated_demand]).to eq(BigDecimal("9"))
      expect(result[root.id][:aggregated_demand]).to eq(BigDecimal("10"))
    end

    it "aggregates a deep tree without depending on the Ruby call stack" do
      node_class = Struct.new(:id, :ancestry, :demand_type, :demand_value, :subtree)
      nodes = 10_000.times.map do |index|
        ancestry = index.zero? ? nil : index.to_s
        node_class.new(index + 1, ancestry, "fixed", BigDecimal("1"), nil)
      end
      nodes.first.subtree = nodes

      result = described_class.aggregate_demand(nodes.first)

      expect(result[nodes.first.id][:aggregated_demand]).to eq(BigDecimal("10000"))
      expect(result[nodes.last.id][:aggregated_demand]).to eq(BigDecimal("1"))
    end

    it "excludes a binary leaf's magnitude from the numeric parent's sum, but counts it", :aggregate_failures do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)
      binary_leaf = Custodian::Core::Node.create!(demand_type: "binary", parent: root)

      result = described_class.aggregate_demand(root)

      expect(result[binary_leaf.id][:own_demand]).to be_nil
      expect(result[binary_leaf.id][:aggregated_demand]).to be_nil
      expect(result[binary_leaf.id][:binary]).to be true
      expect(result[binary_leaf.id][:unresolved_binary_count]).to eq(1)

      expect(result[root.id][:aggregated_demand]).to eq(BigDecimal("10"))
      expect(result[root.id][:unresolved_binary_count]).to eq(1)
    end

    it "does not let a numeric grandchild's demand tunnel through a binary parent to the numeric grandparent" do
      grandparent = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)
      binary_parent = Custodian::Core::Node.create!(demand_type: "binary", parent: grandparent)
      Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 999, parent: binary_parent)

      result = described_class.aggregate_demand(grandparent)

      expect(result[binary_parent.id][:aggregated_demand]).to be_nil
      expect(result[grandparent.id][:aggregated_demand]).to eq(BigDecimal("10"))
    end

    context "with a mixed tree (numeric, binary, and a firewalled binary/numeric branch)" do
      let!(:root) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10) }
      let!(:child_a) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 5, parent: root) }
      let!(:child_b) { Custodian::Core::Node.create!(demand_type: "binary", parent: root) }
      let!(:child_c) { Custodian::Core::Node.create!(demand_type: "binary", parent: root) }
      let!(:grandchild) { Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 999, parent: child_c) }

      it "computes own_demand/aggregated_demand/binary/unresolved_binary_count for the leaves" do
        result = described_class.aggregate_demand(root)

        expect(result[grandchild.id]).to eq(
          own_demand: BigDecimal("999"), aggregated_demand: BigDecimal("999"),
          binary: false, unresolved_binary_count: 0
        )
        expect(result[child_a.id]).to eq(
          own_demand: BigDecimal("5"), aggregated_demand: BigDecimal("5"),
          binary: false, unresolved_binary_count: 0
        )
      end

      it "computes binary: true and own/aggregated_demand: nil for the two binary nodes" do
        result = described_class.aggregate_demand(root)

        expect(result[child_b.id]).to eq(
          own_demand: nil, aggregated_demand: nil, binary: true, unresolved_binary_count: 1
        )
        expect(result[child_c.id]).to eq(
          own_demand: nil, aggregated_demand: nil, binary: true, unresolved_binary_count: 1
        )
      end

      it "computes the root's aggregated_demand (numeric children only) and total binary count" do
        result = described_class.aggregate_demand(root)

        expect(result[root.id]).to eq(
          own_demand: BigDecimal("10"), aggregated_demand: BigDecimal("15"),
          binary: false, unresolved_binary_count: 2
        )
      end
    end

    it "runs within a fixed small number of queries regardless of tree size (no N+1)" do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 1)
      20.times do
        Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 1, parent: root)
      end

      query_count = count_queries { described_class.aggregate_demand(root) }

      expect(query_count).to be <= 3
    end

    it "does exact BigDecimal arithmetic, never Float" do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: "0.1")
      Custodian::Core::Node.create!(demand_type: "fixed", demand_value: "0.2", parent: root)

      result = described_class.aggregate_demand(root)

      expect(result[root.id][:aggregated_demand]).to eq(BigDecimal("0.3"))
      expect(result[root.id][:aggregated_demand]).to be_a(BigDecimal)
      expect(0.1 + 0.2).not_to eq(0.3) # sanity check: Float arithmetic would have failed this
    end

    it "does not mutate any record (updated_at is untouched)" do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)
      child = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 5, parent: root)
      root_updated_at = root.reload.updated_at
      child_updated_at = child.reload.updated_at

      described_class.aggregate_demand(root)

      expect(root.reload.updated_at).to eq(root_updated_at)
      expect(child.reload.updated_at).to eq(child_updated_at)
    end
  end
end
