# frozen_string_literal: true

module Custodian
  module Core
    class CustodyRepudiatedNode < ApplicationRecord
      self.table_name = "custodian_core_custody_repudiated_nodes"

      belongs_to :custody, class_name: "Custodian::Core::Custody"
      belongs_to :node, class_name: "Custodian::Core::Node"

      validates :custody_id, uniqueness: { scope: :node_id }
    end
  end
end
