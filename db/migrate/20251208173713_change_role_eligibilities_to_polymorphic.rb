class ChangeRoleEligibilitiesToPolymorphic < ActiveRecord::Migration[8.1]
  def change
    # Remove the foreign key constraint on person_id
    remove_foreign_key :role_eligibilities, :people

    # Rename person_id to member_id
    rename_column :role_eligibilities, :person_id, :member_id

    # Add member_type column for polymorphic association
    add_column :role_eligibilities, :member_type, :string, null: false, default: "Person"

    # Update existing records to have the correct member_type (they're all Person)
    # Default already handles this

    # Remove the default after migration
    change_column_default :role_eligibilities, :member_type, nil

    # Remove the old index and add a new one for the polymorphic association
    remove_index :role_eligibilities, [ :role_id, :person_id ], if_exists: true
    add_index :role_eligibilities, [ :role_id, :member_type, :member_id ], unique: true, name: "index_role_eligibilities_on_role_and_member"
  end
end
