# frozen_string_literal: true

module Custodian
  module Core
    class Node < ActiveRecord::Base
      self.table_name = "custodian_core_nodes"

      validate :demand_value_absent_when_binary

      private

      def demand_value_absent_when_binary
        return unless demand_type == "binary" && demand_value.present?

        errors.add(:demand_value, "must be blank when demand_type is binary")
      end
    end
  end
end
