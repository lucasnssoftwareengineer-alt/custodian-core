# frozen_string_literal: true

require "bigdecimal"

module Custodian
  module Core
    module Adjuster
      class << self
        # Computes, for every node in root_node's subtree, its consolidated
        # demand (own demand_value + aggregated demand_value of numeric
        # descendants). Pure calculation: no persistence, no ActionRegistry
        # calls, no mutation of any record.
        #
        # Loads the whole subtree in a single query, then works entirely in
        # memory (children are grouped by parent_id parsed from the ancestry
        # column, never via DB-querying association methods) so the query
        # count does not scale with tree size.
        def aggregate_demand(root_node)
          nodes = root_node.subtree.to_a
          children_by_parent_id = nodes.group_by { |node| parent_id_of(node) }

          results = {}
          post_order(root_node, children_by_parent_id) do |node|
            results[node.id] = compute(node, children_by_parent_id[node.id] || [], results)
          end
          results
        end

        private

        def parent_id_of(node)
          return nil if node.ancestry.nil?

          node.ancestry.split("/").last.to_i
        end

        def post_order(node, children_by_parent_id, &block)
          (children_by_parent_id[node.id] || []).each { |child| post_order(child, children_by_parent_id, &block) }
          block.call(node)
        end

        def compute(node, children, results)
          binary = node.demand_type == "binary"
          # Binary children are a magnitude firewall: their own aggregated_demand
          # is nil and their numeric descendants never tunnel through them.
          numeric_children = children.reject { |child| results[child.id][:binary] }
          numeric_children_sum = numeric_children.sum(BigDecimal("0")) { |child| results[child.id][:aggregated_demand] }
          unresolved_binary_count = (binary ? 1 : 0) + children.sum { |child| results[child.id][:unresolved_binary_count] }

          {
            own_demand: binary ? nil : node.demand_value,
            aggregated_demand: binary ? nil : node.demand_value + numeric_children_sum,
            binary: binary,
            unresolved_binary_count: unresolved_binary_count
          }
        end
      end
    end
  end
end
