# frozen_string_literal: true

module Custodian
  module Core
    module ActionRegistry
      @registry = {}
      @mutex = Mutex.new

      class << self
        def register(action_name, &block)
          name = action_name.to_sym
          @mutex.synchronize { @registry[name] = block }
        end

        def call(action_name, node, custody, remaining)
          name = action_name.to_sym
          block = @mutex.synchronize { @registry[name] }
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
