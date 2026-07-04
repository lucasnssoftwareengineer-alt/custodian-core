# frozen_string_literal: true

RSpec.describe Custodian::Core::Custody do
  describe "creation" do
    it "can be created with a ward, action_name, and default priority_weight" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")

      custody = described_class.create!(ward: ward, action_name: "notify")

      expect(custody.priority_weight).to eq(0)
    end
  end

  describe "custodian" do
    it "can be polymorphically associated to an arbitrary ActiveRecord class" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")
      host_object = DummyHostObject.create!

      custody = described_class.create!(ward: ward, action_name: "notify", custodian: host_object)

      expect(custody.reload.custodian).to eq(host_object)
    end

    it "can also be another Node, without any special-casing" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")
      custodian_node = Custodian::Core::Node.create!(demand_type: "binary")

      custody = described_class.create!(ward: ward, action_name: "notify", custodian: custodian_node)

      expect(custody.reload.custodian).to eq(custodian_node)
    end
  end
end
