# frozen_string_literal: true

RSpec.describe Custodian::Core::ActionRegistry do
  # The registry is transport, not logic: it doesn't care what node/custody
  # actually are, so plain doubles are enough to prove arguments pass through.
  let(:node) { double("node") }
  let(:custody) { double("custody") }

  around do |example|
    described_class.clear!
    example.run
    described_class.clear!
  end

  describe "register + call" do
    it "passes node, custody, and remaining through to the registered block, and returns its value" do
      received_args = nil
      described_class.register(:notify) do |n, c, remaining|
        received_args = [n, c, remaining]
        :resolved
      end

      result = described_class.call(:notify, node, custody, 42)

      expect(received_args).to eq([node, custody, 42])
      expect(result).to eq(:resolved)
    end

    it "treats String and Symbol action names as equivalent" do
      described_class.register("store") { |_n, _c, _remaining| :resolved }

      result = described_class.call(:store, node, custody, 0)

      expect(result).to eq(:resolved)
    end
  end

  describe "error handling" do
    it "raises NotRegisteredError, naming the action, when calling an unregistered name" do
      expect { described_class.call(:ghost, node, custody, 0) }
        .to raise_error(Custodian::Core::ActionRegistry::NotRegisteredError, /ghost/)
    end

    it "raises AlreadyRegisteredError, naming the action, when registering the same name twice" do
      described_class.register(:notify) { |_n, _c, _remaining| :resolved }

      expect { described_class.register(:notify) { |_n, _c, _remaining| :resolved } }
        .to raise_error(Custodian::Core::ActionRegistry::AlreadyRegisteredError, /notify/)
    end
  end

  describe "#unregister" do
    it "removes a registered action, flipping registered? to false and making call raise afterwards" do
      described_class.register(:notify) { |_n, _c, _remaining| :resolved }

      described_class.unregister(:notify)

      expect(described_class.registered?(:notify)).to be false
      expect { described_class.call(:notify, node, custody, 0) }
        .to raise_error(Custodian::Core::ActionRegistry::NotRegisteredError, /notify/)
    end

    it "raises NotRegisteredError when unregistering an action that was never registered" do
      expect { described_class.unregister(:ghost) }
        .to raise_error(Custodian::Core::ActionRegistry::NotRegisteredError, /ghost/)
    end
  end

  describe "outcome validation" do
    it "passes through :resolved, :failed, and a Numeric" do
      [:resolved, :failed, 42.5].each do |outcome|
        described_class.register(:action) { |_n, _c, _remaining| outcome }

        expect(described_class.call(:action, node, custody, 0)).to eq(outcome)

        described_class.unregister(:action)
      end
    end

    it "raises InvalidOutcomeError naming the action and showing the invalid return value" do
      [true, nil, "resolved"].each do |bad_outcome|
        described_class.register(:action) { |_n, _c, _remaining| bad_outcome }

        expect { described_class.call(:action, node, custody, 0) }
          .to raise_error(Custodian::Core::ActionRegistry::InvalidOutcomeError) { |error|
            expect(error.message).to include(":action")
            expect(error.message).to include(bad_outcome.inspect)
          }

        described_class.unregister(:action)
      end
    end
  end
end
