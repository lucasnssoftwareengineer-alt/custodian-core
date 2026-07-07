# frozen_string_literal: true

module Custodian
  module Core
    module ActionRegistry
      class AlreadyRegisteredError < Custodian::Core::Error; end
      class NotRegisteredError < Custodian::Core::Error; end

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

          block.call(node, custody, remaining)
        end

        # Removes all registrations. Intended for test isolation: call this
        # in a before/around hook so each spec starts from a clean registry.
        def clear!
          @mutex.synchronize { @registry.clear }
        end
      end
    end
  end
end
