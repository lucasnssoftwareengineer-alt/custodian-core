# frozen_string_literal: true

class CreateCustodianCoreNodes < ActiveRecord::Migration[7.0]
  def change
    create_table :custodian_core_nodes do |t|
      t.string :ancestry, index: true

      t.string :subject_type
      t.bigint :subject_id

      t.string :demand_type, null: false
      t.decimal :demand_value, precision: 15, scale: 4

      t.timestamps
    end

    add_index :custodian_core_nodes, %i[subject_type subject_id]
  end
end
