# frozen_string_literal: true

RSpec.describe Custodian::Core::Graph do
  describe "root_node validity" do
    it "can be created with a valid root Node (no parent)" do
      root = Custodian::Core::Node.create!(demand_type: "binary")

      graph = described_class.new(root_node: root)

      expect(graph).to be_valid
    end

    it "is invalid when root_node has a parent" do
      root = Custodian::Core::Node.create!(demand_type: "binary")
      child = Custodian::Core::Node.create!(demand_type: "binary", parent: root)

      graph = described_class.new(root_node: child)

      expect(graph).not_to be_valid
      expect(graph.errors[:root_node]).not_to be_empty
    end
  end
end
