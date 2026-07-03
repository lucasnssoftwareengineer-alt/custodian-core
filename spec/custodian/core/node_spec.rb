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

    it "is valid when demand_type is fixed and demand_value is present" do
      node = described_class.new(demand_type: "fixed", demand_value: 10)

      expect(node).to be_valid
    end

    it "is invalid when demand_type is fixed and demand_value is absent" do
      node = described_class.new(demand_type: "fixed")

      expect(node).not_to be_valid
      expect(node.errors[:demand_value]).not_to be_empty
    end
  end

  describe "ancestry" do
    it "supports a tree of parents and children" do
      root = described_class.create!(demand_type: "binary")
      child = described_class.create!(demand_type: "binary", parent: root)
      grandchild = described_class.create!(demand_type: "binary", parent: child)

      expect(grandchild.root).to eq(root)
      expect(root.children).to contain_exactly(child)
      expect(root.subtree).to contain_exactly(root, child, grandchild)
      expect(grandchild.ancestor_ids).to eq([root.id, child.id])
    end
  end

  describe "polymorphic subject" do
    it "can be associated to an arbitrary ActiveRecord class" do
      host_object = DummyHostObject.create!

      node = described_class.create!(demand_type: "binary", subject: host_object)

      expect(node.reload.subject).to eq(host_object)
    end
  end
end
