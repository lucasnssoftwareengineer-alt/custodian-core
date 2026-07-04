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

  describe "action_params" do
    it "defaults to an empty hash" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")

      custody = described_class.create!(ward: ward, action_name: "notify")

      expect(custody.reload.action_params).to eq({})
    end

    it "round-trips arbitrary nested data through the database" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")
      params = { "amount" => 42, "nested" => { "currency" => "BRL", "tags" => %w[a b] } }

      custody = described_class.create!(ward: ward, action_name: "notify", action_params: params)

      expect(custody.reload.action_params).to eq(params)
    end
  end

  describe "#currently_valid?" do
    let(:ward) { Custodian::Core::Node.create!(demand_type: "binary") }

    context "when validity_type is eternal" do
      it "is true regardless of any dates set" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "eternal",
          valid_from: 10.years.ago, valid_until: 10.years.ago
        )

        expect(custody.currently_valid?).to be true
      end
    end

    context "when validity_type is fixed_term" do
      it "is true within [valid_from, valid_until]" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "fixed_term",
          valid_from: 1.day.ago, valid_until: 1.day.from_now
        )

        expect(custody.currently_valid?).to be true
      end

      it "is false before valid_from" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "fixed_term",
          valid_from: 1.day.from_now, valid_until: 2.days.from_now
        )

        expect(custody.currently_valid?).to be false
      end

      it "is false after valid_until" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "fixed_term",
          valid_from: 2.days.ago, valid_until: 1.day.ago
        )

        expect(custody.currently_valid?).to be false
      end

      it "treats a nil valid_from as unbounded on that side" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "fixed_term",
          valid_from: nil, valid_until: 1.day.from_now
        )

        expect(custody.currently_valid?).to be true
      end

      it "treats a nil valid_until as unbounded on that side" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "fixed_term",
          valid_from: 1.day.ago, valid_until: nil
        )

        expect(custody.currently_valid?).to be true
      end
    end

    context "when validity_type is punctual" do
      it "is true at or before valid_until" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "punctual", valid_until: Time.current
        )

        expect(custody.currently_valid?(custody.valid_until)).to be true
        expect(custody.currently_valid?(custody.valid_until - 1.hour)).to be true
      end

      it "is false after valid_until" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "punctual", valid_until: 1.day.ago
        )

        expect(custody.currently_valid?).to be false
      end

      it "ignores valid_from entirely" do
        custody = described_class.create!(
          ward: ward, action_name: "notify", validity_type: "punctual",
          valid_from: 1.day.from_now, valid_until: 1.day.from_now
        )

        expect(custody.currently_valid?).to be true
      end
    end

    context "when status is broken or expired" do
      it "is false even though validity_type/dates would otherwise say valid" do
        %w[broken expired].each do |status|
          custody = described_class.create!(
            ward: ward, action_name: "notify", validity_type: "eternal", status: status
          )

          expect(custody.currently_valid?).to be false
        end
      end
    end
  end

  describe "#at_risk?" do
    it "is true when status is at_risk, false for all other statuses" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")

      %w[active at_risk broken expired].each do |status|
        custody = described_class.create!(ward: ward, action_name: "notify", status: status)

        expect(custody.at_risk?).to eq(status == "at_risk")
      end
    end
  end

  describe "#trustworthy?" do
    it "is false when status is broken" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")
      custody = described_class.create!(ward: ward, action_name: "notify", validity_type: "eternal", status: "broken")

      expect(custody.trustworthy?).to be false
    end

    it "is false when status is expired" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")
      custody = described_class.create!(
        ward: ward, action_name: "notify", validity_type: "eternal", status: "expired"
      )

      expect(custody.trustworthy?).to be false
    end

    it "is false when status is at_risk, even though currently_valid? is true for the same Custody" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")
      custody = described_class.create!(
        ward: ward, action_name: "notify", validity_type: "eternal", status: "at_risk"
      )

      expect(custody.currently_valid?).to be true
      expect(custody.trustworthy?).to be false
    end

    it "is true when status is active and validity holds" do
      ward = Custodian::Core::Node.create!(demand_type: "binary")
      custody = described_class.create!(
        ward: ward, action_name: "notify", validity_type: "eternal", status: "active"
      )

      expect(custody.trustworthy?).to be true
    end
  end
end
