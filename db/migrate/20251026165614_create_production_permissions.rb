# frozen_string_literal: true

class CreateProductionPermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :production_permissions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :production, null: false, foreign_key: true
      t.string :role, null: false

      t.timestamps
    end

    add_index :production_permissions, %i[user_id production_id], unique: true
  end
end
