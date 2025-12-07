# frozen_string_literal: true

class CreateGroupInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :group_invitations do |t|
      t.string :email, null: false
      t.references :group, null: false, foreign_key: true
      t.string :token, null: false
      t.integer :permission_level, default: 2, null: false
      t.datetime :accepted_at
      t.integer :invited_by_person_id
      t.string :name, null: false

      t.timestamps
    end

    add_index :group_invitations, :token, unique: true
    add_index :group_invitations, :email
  end
end
