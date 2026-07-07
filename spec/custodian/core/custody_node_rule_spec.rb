# frozen_string_literal: true

RSpec.describe Custodian::Core::CustodyNodeRule do
  let(:ward) { Custodian::Core::Node.create!(demand_type: "binary") }
  let(:custody) { Custodian::Core::Custody.create!(ward: ward, action_name: "notify") }
  let(:node) { Custodian::Core::Node.create!(demand_type: "binary", parent: ward) }

  describe "rule_type/rule_value" do
    it "is valid with rule_type exclude and no rule_value" do
      rule = described_class.new(custody: custody, node: node, rule_type: "exclude")

      expect(rule).to be_valid
    end

    it "is invalid with rule_type exclude and a rule_value" do
      rule = described_class.new(custody: custody, node: node, rule_type: "exclude", rule_value: 10)

      expect(rule).not_to be_valid
      expect(rule.errors[:rule_value]).not_to be_empty
    end

    it "is valid with rule_type limit_pct and rule_value 50" do
      rule = described_class.new(custody: custody, node: node, rule_type: "limit_pct", rule_value: 50)

      expect(rule).to be_valid
    end

    it "is invalid with rule_type limit_pct and no rule_value" do
      rule = described_class.new(custody: custody, node: node, rule_type: "limit_pct")

      expect(rule).not_to be_valid
      expect(rule.errors[:rule_value]).not_to be_empty
    end
  end
end
