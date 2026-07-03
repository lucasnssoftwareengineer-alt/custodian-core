# frozen_string_literal: true

require "rails"

module Custodian
  module Core
    class Engine < ::Rails::Engine
      isolate_namespace Custodian::Core
    end
  end
end
