# frozen_string_literal: true

class CreateCustodianCoreCustodyNodeRules < ActiveRecord::Migration[7.0]
  def change
    create_table :custodian_core_custody_node_rules do |t|
      t.bigint :custody_id, null: false
      t.bigint :node_id, null: false

      t.string :rule_type, null: false
      t.decimal :rule_value, precision: 15, scale: 4

      t.timestamps
    end

    add_index :custodian_core_custody_node_rules, %i[custody_id node_id],
              unique: true, name: "index_custody_node_rules_on_custody_and_node"
    add_foreign_key :custodian_core_custody_node_rules, :custodian_core_custodies, column: :custody_id
    add_foreign_key :custodian_core_custody_node_rules, :custodian_core_nodes, column: :node_id
  end
end
