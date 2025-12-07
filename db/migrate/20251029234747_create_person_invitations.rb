# frozen_string_literal: true

class CreatePersonInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :person_invitations do |t|
      t.references :production_company, null: false, foreign_key: true
      t.string :email, null: false
      t.string :token, null: false
      t.datetime :accepted_at

      t.timestamps
    end
    add_index :person_invitations, :token, unique: true
  end
end
