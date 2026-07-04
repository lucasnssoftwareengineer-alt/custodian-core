# frozen_string_literal: true

module Custodian
  module Core
    class Custody < ApplicationRecord
      self.table_name = "custodian_core_custodies"

      belongs_to :ward, class_name: "Custodian::Core::Node"
    end
  end
end
