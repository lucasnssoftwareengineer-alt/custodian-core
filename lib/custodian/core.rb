# frozen_string_literal: true

require_relative "core/version"
require_relative "core/engine"

module Custodian
  module Core
    class Error < StandardError; end
  end
end

require_relative "core/action_registry"
