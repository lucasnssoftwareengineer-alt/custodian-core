# frozen_string_literal: true

module Custodian
  module Core
    class Graph < ApplicationRecord
      self.table_name = "custodian_core_graphs"

      belongs_to :owner, polymorphic: true, optional: true
      belongs_to :root_node, class_name: "Custodian::Core::Node"

      validate :root_node_must_be_a_root

      private

      def root_node_must_be_a_root
        return if root_node.nil? || root_node.root?

        errors.add(:root_node, "must be a root node (cannot have a parent)")
      end
    end
  end
end
