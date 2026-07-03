# frozen_string_literal: true

class CreateCustodianCoreGraphs < ActiveRecord::Migration[7.0]
  def change
    create_table :custodian_core_graphs do |t|
      t.string :owner_type
      t.bigint :owner_id

      t.bigint :root_node_id, null: false

      t.timestamps
    end

    add_index :custodian_core_graphs, %i[owner_type owner_id]
    add_foreign_key :custodian_core_graphs, :custodian_core_nodes, column: :root_node_id
  end
end
