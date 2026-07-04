# frozen_string_literal: true

class CreateCustodianCoreCustodies < ActiveRecord::Migration[7.0]
  def change
    create_table :custodian_core_custodies do |t|
      t.string :custodian_type
      t.bigint :custodian_id

      t.bigint :ward_id, null: false

      t.string :action_name, null: false
      t.json :action_params, null: false, default: {}

      t.integer :priority_weight, null: false, default: 0

      t.string :validity_type, null: false, default: "eternal"
      t.datetime :valid_from
      t.datetime :valid_until

      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :custodian_core_custodies, %i[custodian_type custodian_id],
              name: "index_custodian_core_custodies_on_custodian"
    add_foreign_key :custodian_core_custodies, :custodian_core_nodes, column: :ward_id
  end
end
