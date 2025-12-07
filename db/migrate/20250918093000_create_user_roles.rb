# frozen_string_literal: true

class CreateUserRoles < ActiveRecord::Migration[7.0]
  def change
    create_table :user_roles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :production_company, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :user_roles, %i[user_id production_company_id], unique: true
  end
end
