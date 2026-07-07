# frozen_string_literal: true

module Custodian
  module Core
    class Custody < ApplicationRecord
      self.table_name = "custodian_core_custodies"

      VALIDITY_TYPES = %w[eternal fixed_term punctual].freeze
      STATUSES = %w[active at_risk broken expired].freeze

      belongs_to :custodian, polymorphic: true, optional: true
      belongs_to :ward, class_name: "Custodian::Core::Node"

      has_many :node_rules, class_name: "Custodian::Core::CustodyNodeRule", dependent: :destroy
      has_many :repudiated_nodes, class_name: "Custodian::Core::CustodyRepudiatedNode", dependent: :destroy

      validates :action_name, presence: true
      validates :priority_weight, numericality: { only_integer: true }
      validates :validity_type, inclusion: { in: VALIDITY_TYPES }
      validates :status, inclusion: { in: STATUSES }

      # Answers only the exclusion question: is this node repudiated, or does
      # it have an "exclude" rule? It does NOT interpret limit_pct/limit_amount
      # rule values (i.e. it doesn't decide how much of the demand applies) -
      # that quantitative interpretation is the Adjuster's job, in a later step.
      def applies_to?(node)
        return false if repudiated_nodes.exists?(node: node)
        return false if node_rules.exists?(node: node, rule_type: "exclude")

        true
      end

      def at_risk?
        status == "at_risk"
      end

      def trustworthy?(at_time = Time.current)
        currently_valid?(at_time) && !at_risk?
      end

      def healthcheck(at_time = Time.current)
        return :broken if status == "broken"
        return :expired if status == "expired"
        return :expired unless currently_valid?(at_time)
        return :at_risk if at_risk?

        :active
      end

      def currently_valid?(at_time = Time.current)
        return false if %w[broken expired].include?(status)

        case validity_type
        when "eternal"
          true
        when "fixed_term"
          fixed_term_valid_at?(at_time)
        when "punctual"
          punctual_valid_at?(at_time)
        end
      end

      private

      def fixed_term_valid_at?(at_time)
        (valid_from.nil? || at_time >= valid_from) && (valid_until.nil? || at_time <= valid_until)
      end

      def punctual_valid_at?(at_time)
        valid_until.nil? || at_time <= valid_until
      end
    end
  end
end
