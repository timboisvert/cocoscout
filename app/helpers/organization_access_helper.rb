# frozen_string_literal: true

# Access by module, for views (OrganizationAccess): whether the current
# person can see a module, and whether they can change it.
module OrganizationAccessHelper
  def module_access?(module_key, level = :view)
    OrganizationAccess.allows?(Current.user, Current.organization, module_key, level)
  end

  def module_change?(module_key)
    module_access?(module_key, :manage)
  end
end
