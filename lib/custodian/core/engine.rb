# frozen_string_literal: true

require "active_support"
require "active_support/core_ext"
require "action_dispatch"
require "rails/engine"

module Custodian
  module Core
    class Engine < ::Rails::Engine
      isolate_namespace Custodian::Core
    end
  end
end
