# frozen_string_literal: true

class CreateCustodianCoreCustodyRepudiatedNodes < ActiveRecord::Migration[7.0]
  def change
    create_table :custodian_core_custody_repudiated_nodes do |t|
      t.bigint :custody_id, null: false
      t.bigint :node_id, null: false

      t.timestamps
    end

    add_index :custodian_core_custody_repudiated_nodes, %i[custody_id node_id],
              unique: true, name: "index_custody_repudiated_nodes_on_custody_and_node"
    add_foreign_key :custodian_core_custody_repudiated_nodes, :custodian_core_custodies, column: :custody_id
    add_foreign_key :custodian_core_custody_repudiated_nodes, :custodian_core_nodes, column: :node_id
  end
end
