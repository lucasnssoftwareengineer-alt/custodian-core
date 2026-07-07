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
end
