class BackfillUserRolesForExistingCompanies < ActiveRecord::Migration[7.0]
  def up
    ProductionCompany.find_each do |company|
      company.users.find_each do |user|
        unless UserRole.exists?(user: user, production_company: company)
          UserRole.create!(user: user, production_company: company, role: "manager")
        end
      end
    end
  end

  def down
    # No-op: do not remove roles
  end
end
