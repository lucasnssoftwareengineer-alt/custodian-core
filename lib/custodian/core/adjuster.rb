# frozen_string_literal: true

require "bigdecimal"

module Custodian
  module Core
    module Adjuster
      @phases = []

      class << self
        # Registers a resolution phase, run (in registration order) between
        # direct custodies and escalation for every node still unresolved.
        # This is the extension point a future sibling-generosity satellite
        # plugs into; this step only builds the hook, not any phase itself.
        def register_phase(name, handler)
          @phases << { name: name, handler: handler }
        end

        # Removes all registered phases. Intended for test isolation.
        def clear_phases!
          @phases = []
        end

        # Walks root_node's subtree post-order (leaves first), invoking
        # registered actions through each node's custodies, and escalating
        # unresolved demand to the direct parent (see the class docs for the
        # full encapsulation design). Pure resolution: never persists or
        # mutates any Node/Custody record. Actions themselves may have side
        # effects; that is their business, not the Adjuster's.
        def resolve_tree(root_node, strictness: :valid)
          nodes = root_node.subtree.to_a
          children_by_parent_id = nodes.group_by { |node| parent_id_of(node) }
          custodies_by_ward_id = Custody.where(ward_id: nodes.map(&:id))
                                         .order(:priority_weight, :id)
                                         .group_by(&:ward_id)

          results = {}
          post_order(root_node, children_by_parent_id) do |node|
            results[node.id] = resolve_node(node, custodies_by_ward_id[node.id] || [], strictness)
          end
          results
        end

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

          {
            own_demand: binary ? nil : node.demand_value,
            aggregated_demand: binary ? nil : node.demand_value + numeric_children_sum(children, results),
            binary: binary,
            unresolved_binary_count: unresolved_binary_count(binary, children, results)
          }
        end

        # Binary children are a magnitude firewall: their own aggregated_demand
        # is nil and their numeric descendants never tunnel through them.
        def numeric_children_sum(children, results)
          children.reject { |child| results[child.id][:binary] }
                  .sum(BigDecimal("0")) { |child| results[child.id][:aggregated_demand] }
        end

        def unresolved_binary_count(binary, children, results)
          (binary ? 1 : 0) + children.sum { |child| results[child.id][:unresolved_binary_count] }
        end

        def resolve_node(node, custodies, _strictness)
          binary = node.demand_type == "binary"
          own_demand = binary ? nil : node.demand_value
          remaining = own_demand || BigDecimal("0")
          attempts = []

          custodies.each do |custody|
            outcome = ActionRegistry.call(custody.action_name, node, custody, remaining)
            attempts << { custody_id: custody.id, action_name: custody.action_name, outcome: outcome, via: :direct }

            case outcome
            when :resolved
              remaining = BigDecimal("0")
              break
            when :failed
              next
            else
              remaining -= outcome
            end
            break if remaining.zero?
          end

          {
            demanded: binary ? nil : own_demand,
            own_demand: own_demand,
            inherited_shortfall: BigDecimal("0"),
            resolved_amount: binary ? nil : (own_demand - remaining),
            gap: binary ? nil : remaining,
            binary: binary,
            binary_resolved: nil,
            pending_binaries_escalated: [],
            attempts: attempts
          }
        end
      end
    end
  end
end
