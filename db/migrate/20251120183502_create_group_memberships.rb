class CreateGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :group_memberships do |t|
      t.references :group, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.integer :permission_level, null: false, default: 0
      t.text :notification_preferences

      t.timestamps
    end

    add_index :group_memberships, [ :group_id, :person_id ], unique: true
  end
end
