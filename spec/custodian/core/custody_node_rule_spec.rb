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

    it "is invalid with rule_type limit_pct and rule_value 0 or 150 (boundary checks)" do
      [0, 150].each do |value|
        rule = described_class.new(custody: custody, node: node, rule_type: "limit_pct", rule_value: value)

        expect(rule).not_to be_valid
        expect(rule.errors[:rule_value]).not_to be_empty
      end
    end
  end

  describe "uniqueness of [custody, node]" do
    it "rejects a duplicate rule for the same custody/node pair at the model level" do
      described_class.create!(custody: custody, node: node, rule_type: "exclude")
      duplicate = described_class.new(custody: custody, node: node, rule_type: "full")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:custody_id]).not_to be_empty
    end

    it "rejects a duplicate rule for the same custody/node pair at the database level, " \
       "even when model validation is skipped" do
      described_class.create!(custody: custody, node: node, rule_type: "exclude")
      duplicate = described_class.new(custody: custody, node: node, rule_type: "full")

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
