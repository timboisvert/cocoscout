# frozen_string_literal: true

class CreateInvitations < ActiveRecord::Migration[7.0]
  def change
    create_table :invitations do |t|
      t.references :production_company, null: false, foreign_key: true
      t.string :email, null: false
      t.string :token, null: false
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :invitations, :token, unique: true
  end
end
