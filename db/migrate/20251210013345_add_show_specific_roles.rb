class AddShowSpecificRoles < ActiveRecord::Migration[8.1]
  def change
    # Add use_custom_roles flag to shows
    add_column :shows, :use_custom_roles, :boolean, default: false, null: false

    # Create show_roles table (show-specific roles)
    create_table :show_roles do |t|
      t.references :show, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position
      t.boolean :restricted, default: false, null: false

      t.timestamps
    end

    add_index :show_roles, [ :show_id, :name ], unique: true
    add_index :show_roles, [ :show_id, :position ]

    # Create show_role_eligibilities table (who can be cast in restricted show roles)
    create_table :show_role_eligibilities do |t|
      t.references :show_role, null: false, foreign_key: true
      t.string :member_type, null: false
      t.integer :member_id, null: false

      t.timestamps
    end

    add_index :show_role_eligibilities, [ :show_role_id, :member_type, :member_id ],
              unique: true, name: "index_show_role_eligibilities_on_role_and_member"
    add_index :show_role_eligibilities, [ :member_type, :member_id ],
              name: "index_show_role_eligibilities_on_member"

    # Add show_role_id to show_person_role_assignments (for custom role assignments)
    add_reference :show_person_role_assignments, :show_role, foreign_key: true, null: true

    # Make role_id nullable (since assignments can now use either role_id or show_role_id)
    change_column_null :show_person_role_assignments, :role_id, true
  end
end
