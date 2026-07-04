# frozen_string_literal: true

RSpec.describe Custodian::Core::Custody do
  describe "creation" do
    it "can be created with a ward, action_name, and default priority_weight" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")

      custody = described_class.create!(ward: ward, action_name: "notify")

      expect(custody.priority_weight).to eq(0)
    end
  end
end
