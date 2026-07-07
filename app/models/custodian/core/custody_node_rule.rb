# frozen_string_literal: true

module Custodian
  module Core
    class CustodyNodeRule < ApplicationRecord
      self.table_name = "custodian_core_custody_node_rules"

      RULE_TYPES = %w[exclude full limit_pct limit_amount].freeze

      belongs_to :custody, class_name: "Custodian::Core::Custody"
      belongs_to :node, class_name: "Custodian::Core::Node"

      validates :rule_type, inclusion: { in: RULE_TYPES }
      validate :rule_value_matches_rule_type

      scope :for_node, ->(node) { where(node: node) }

      private

      def rule_value_matches_rule_type
        if %w[exclude full].include?(rule_type)
          errors.add(:rule_value, "must be blank when rule_type is #{rule_type}") if rule_value.present?
        elsif rule_value.nil?
          errors.add(:rule_value, "can't be blank when rule_type is #{rule_type}")
        end
      end
    end
  end
end
