# frozen_string_literal: true

RSpec.describe Custodian::Core::Node do
  describe "demand_type/demand_value" do
    it "is valid when demand_type is binary and demand_value is absent" do
      node = described_class.new(demand_type: "binary")

      expect(node).to be_valid
    end

    it "is invalid when demand_type is binary and demand_value is present" do
      node = described_class.new(demand_type: "binary", demand_value: 10)

      expect(node).not_to be_valid
      expect(node.errors[:demand_value]).not_to be_empty
    end
  end
end
