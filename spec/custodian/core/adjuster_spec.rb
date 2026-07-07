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

    it "excludes a binary leaf's magnitude from the numeric parent's sum, but counts it" do
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

    it "computes the full Hash for every node in a mixed tree", :aggregate_failures do
      root = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 10)
      child_a = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 5, parent: root)
      child_b = Custodian::Core::Node.create!(demand_type: "binary", parent: root)
      child_c = Custodian::Core::Node.create!(demand_type: "binary", parent: root)
      grandchild = Custodian::Core::Node.create!(demand_type: "fixed", demand_value: 999, parent: child_c)

      result = described_class.aggregate_demand(root)

      expect(result[grandchild.id]).to eq(
        own_demand: BigDecimal("999"), aggregated_demand: BigDecimal("999"),
        binary: false, unresolved_binary_count: 0
      )
      expect(result[child_a.id]).to eq(
        own_demand: BigDecimal("5"), aggregated_demand: BigDecimal("5"),
        binary: false, unresolved_binary_count: 0
      )
      expect(result[child_b.id]).to eq(
        own_demand: nil, aggregated_demand: nil, binary: true, unresolved_binary_count: 1
      )
      expect(result[child_c.id]).to eq(
        own_demand: nil, aggregated_demand: nil, binary: true, unresolved_binary_count: 1
      )
      expect(result[root.id]).to eq(
        own_demand: BigDecimal("10"), aggregated_demand: BigDecimal("15"),
        binary: false, unresolved_binary_count: 2
      )
    end
  end
end
