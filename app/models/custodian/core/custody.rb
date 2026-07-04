# frozen_string_literal: true

module Custodian
  module Core
    class Custody < ApplicationRecord
      self.table_name = "custodian_core_custodies"

      belongs_to :custodian, polymorphic: true, optional: true
      belongs_to :ward, class_name: "Custodian::Core::Node"

      def currently_valid?(at_time = Time.current)
        case validity_type
        when "eternal"
          true
        when "fixed_term"
          (valid_from.nil? || at_time >= valid_from) && (valid_until.nil? || at_time <= valid_until)
        when "punctual"
          valid_until.nil? || at_time <= valid_until
        end
      end
    end
  end
end
