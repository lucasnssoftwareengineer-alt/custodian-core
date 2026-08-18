# frozen_string_literal: true

require "ancestry"

module Custodian
  module Core
    class Node < ApplicationRecord
      self.table_name = "custodian_core_nodes"

      has_ancestry

      belongs_to :subject, polymorphic: true, optional: true

      DEMAND_TYPES = %w[binary fixed variable_manual variable_by_tag].freeze

      validates :demand_type, presence: true, inclusion: { in: DEMAND_TYPES }
      validates :demand_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validate :demand_value_matches_demand_type

      # Node deliberately has no graph_id column: graph membership is resolved
      # via the ancestry root instead, to avoid an unused foreign key.
      def graph
        Graph.find_by(root_node: root)
      end

      private

      def demand_value_matches_demand_type
        if demand_type == "binary"
          errors.add(:demand_value, "must be blank when demand_type is binary") if demand_value.present?
        elsif demand_value.nil?
          errors.add(:demand_value, "can't be blank unless demand_type is binary")
        end
      end
    end
  end
end
