# frozen_string_literal: true

RSpec.describe Custodian::Core::CustodyRepudiatedNode do
  let(:ward) { Custodian::Core::Node.create!(demand_type: "binary") }
  let(:custody) { Custodian::Core::Custody.create!(ward: ward, action_name: "notify") }
  let(:node) { Custodian::Core::Node.create!(demand_type: "binary", parent: ward) }

  describe "uniqueness of [custody, node]" do
    it "rejects a duplicate repudiation for the same custody/node pair at the model level" do
      described_class.create!(custody: custody, node: node)
      duplicate = described_class.new(custody: custody, node: node)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:custody_id]).not_to be_empty
    end

    it "rejects a duplicate repudiation for the same custody/node pair at the database level, " \
       "even when model validation is skipped" do
      described_class.create!(custody: custody, node: node)
      duplicate = described_class.new(custody: custody, node: node)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
