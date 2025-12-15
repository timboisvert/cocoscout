class RenameNoneToMemberInOrganizationRoles < ActiveRecord::Migration[8.1]
  def up
    OrganizationRole.where(company_role: "none").update_all(company_role: "member")
  end

  def down
    OrganizationRole.where(company_role: "member").update_all(company_role: "none")
  end
end
