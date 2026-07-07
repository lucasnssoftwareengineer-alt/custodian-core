# frozen_string_literal: true

module Custodian
  module Core
    module ActionRegistry
      class AlreadyRegisteredError < Custodian::Core::Error; end
      class NotRegisteredError < Custodian::Core::Error; end
      class InvalidOutcomeError < Custodian::Core::Error; end

      VALID_SYMBOL_OUTCOMES = %i[resolved failed].freeze

      @registry = {}
      @mutex = Mutex.new

      class << self
        def register(action_name, &block)
          name = action_name.to_sym
          @mutex.synchronize do
            raise AlreadyRegisteredError, "action #{name.inspect} is already registered" if @registry.key?(name)

            @registry[name] = block
          end
        end

        def call(action_name, node, custody, remaining)
          name = action_name.to_sym
          block = @mutex.synchronize { @registry[name] }
          raise NotRegisteredError, "action #{name.inspect} is not registered" unless block

          outcome = block.call(node, custody, remaining)
          validate_outcome!(name, outcome)
          outcome
        end

        def unregister(action_name)
          name = action_name.to_sym
          @mutex.synchronize do
            raise NotRegisteredError, "action #{name.inspect} is not registered" unless @registry.key?(name)

            @registry.delete(name)
          end
        end

        def registered?(action_name)
          @mutex.synchronize { @registry.key?(action_name.to_sym) }
        end

        # Removes all registrations. Intended for test isolation: call this
        # in a before/around hook so each spec starts from a clean registry.
        def clear!
          @mutex.synchronize { @registry.clear }
        end

        # Public so callers outside the registry (e.g. Adjuster's phase
        # hook) can validate an outcome using the exact same rule that
        # governs actions invoked through #call: :resolved, :failed, or a
        # non-negative Numeric.
        def validate_outcome!(name, outcome)
          return if VALID_SYMBOL_OUTCOMES.include?(outcome)

          if outcome.is_a?(Numeric)
            # An action must not INCREASE demand: a negative Numeric would mean
            # partial resolution made things worse, which is never valid.
            return if outcome >= 0

            raise InvalidOutcomeError,
                  "action #{name.inspect} returned a negative Numeric outcome: #{outcome.inspect} " \
                  "(an action must not increase demand; Numeric outcomes must be >= 0)"
          end

          raise InvalidOutcomeError,
                "action #{name.inspect} returned an invalid outcome: #{outcome.inspect} " \
                "(expected :resolved, :failed, or a Numeric)"
        end
      end
    end
  end
end
