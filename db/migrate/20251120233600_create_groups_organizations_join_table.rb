# frozen_string_literal: true

class CreateGroupsOrganizationsJoinTable < ActiveRecord::Migration[8.1]
  def change
    create_table :groups_organizations, id: false do |t|
      t.integer :group_id, null: false
      t.integer :organization_id, null: false
    end

    add_index :groups_organizations, :group_id
    add_index :groups_organizations, :organization_id
    add_index :groups_organizations, %i[group_id organization_id], unique: true
  end
end
