# frozen_string_literal: true

module Custodian
  module Core
    class Custody < ApplicationRecord
      self.table_name = "custodian_core_custodies"

      VALIDITY_TYPES = %w[eternal fixed_term punctual].freeze
      STATUSES = %w[active at_risk broken expired].freeze

      belongs_to :custodian, polymorphic: true, optional: true
      belongs_to :ward, class_name: "Custodian::Core::Node"

      validates :action_name, presence: true
      validates :priority_weight, numericality: { only_integer: true }
      validates :validity_type, inclusion: { in: VALIDITY_TYPES }
      validates :status, inclusion: { in: STATUSES }

      def currently_valid?(at_time = Time.current)
        return false if %w[broken expired].include?(status)

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
