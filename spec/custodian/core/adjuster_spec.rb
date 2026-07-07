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
  end
end
