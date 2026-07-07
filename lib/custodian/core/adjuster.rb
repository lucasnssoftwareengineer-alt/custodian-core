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
          parent_id_by_node_id = nodes.each_with_object({}) { |node, hash| hash[node.id] = parent_id_of(node) }
          custodies_by_ward_id = Custody.where(ward_id: nodes.map(&:id))
                                         .order(:priority_weight, :id)
                                         .group_by(&:ward_id)

          results = {}
          inherited_shortfall_by_node_id = Hash.new(BigDecimal("0"))

          post_order(root_node, children_by_parent_id) do |node|
            result = resolve_node(node, custodies_by_ward_id[node.id] || [], strictness,
                                   inherited_shortfall_by_node_id[node.id])
            results[node.id] = result

            parent_id = parent_id_by_node_id[node.id]
            if parent_id && !result[:binary] && result[:gap]&.positive?
              inherited_shortfall_by_node_id[parent_id] += result[:gap]
            end
          end

          settle_numeric_escalations!(results, parent_id_by_node_id, root_node.id)
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

        def resolve_node(node, custodies, strictness, inherited_shortfall)
          binary = node.demand_type == "binary"
          own_demand = binary ? nil : node.demand_value
          total_demand = (own_demand || BigDecimal("0")) + inherited_shortfall
          remaining = total_demand
          attempts = []

          eligible_custodies(custodies, node, strictness).each do |custody|
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
            demanded: binary ? nil : total_demand,
            own_demand: own_demand,
            inherited_shortfall: inherited_shortfall,
            resolved_amount: binary ? nil : (total_demand - remaining),
            gap: binary ? nil : remaining,
            binary: binary,
            binary_resolved: nil,
            pending_binaries_escalated: [],
            attempts: attempts
          }
        end

        # A numeric node that couldn't fully resolve its total_demand (own +
        # already-inherited) has its shortfall folded into the parent's total
        # DURING the main post-order pass (see resolve_tree). Whether that
        # shortfall was EVER actually covered can only be known once we've
        # walked all the way up: a node's escalation is "resolved" if any
        # ancestor's own final gap is zero (that ancestor's custodies covered
        # the whole combined pool, including this node's contribution).
        def settle_numeric_escalations!(results, parent_id_by_node_id, root_id)
          results.each do |node_id, result|
            next if node_id == root_id
            next if result[:binary]
            next unless result[:gap]&.positive?

            if ancestor_resolved?(node_id, parent_id_by_node_id, results)
              result[:gap] = BigDecimal("0")
              result[:attempts] << { custody_id: nil, action_name: nil, outcome: :resolved, via: :escalation }
            else
              result[:attempts] << { custody_id: nil, action_name: nil, outcome: :failed, via: :escalation }
            end
          end
        end

        def ancestor_resolved?(node_id, parent_id_by_node_id, results)
          ancestor_id = parent_id_by_node_id[node_id]
          while ancestor_id
            ancestor_result = results[ancestor_id]
            return true if !ancestor_result[:binary] && ancestor_result[:gap]&.zero?

            ancestor_id = parent_id_by_node_id[ancestor_id]
          end
          false
        end

        # Custodies eligible to act on behalf of `node`: filtered by the
        # caller's chosen strictness (:valid = legal validity only,
        # :trustworthy = also honor risk signals), and by whether the
        # custody actually applies to this specific node (excludes
        # repudiations and "exclude" rules; see Custody#applies_to?).
        def eligible_custodies(custodies, node, strictness)
          custodies.select do |custody|
            valid_under_strictness?(custody, strictness) && custody.applies_to?(node)
          end
        end

        def valid_under_strictness?(custody, strictness)
          case strictness
          when :valid then custody.currently_valid?
          when :trustworthy then custody.trustworthy?
          end
        end
      end
    end
  end
end
