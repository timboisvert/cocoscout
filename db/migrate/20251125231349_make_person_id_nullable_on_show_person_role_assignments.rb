class MakePersonIdNullableOnShowPersonRoleAssignments < ActiveRecord::Migration[8.1]
  def change
    change_column_null :show_person_role_assignments, :person_id, true
  end
end
