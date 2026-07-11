class AddDepartmentToOrganizationStaffMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_staff_members, :department, :string
  end
end
