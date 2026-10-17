# frozen_string_literal: true

# What a production team viewer is shown (Tim, 2026-10-17): they look,
# managers change things. The controllers' ensure_user_is_manager is the
# rule; this and current_user_can_manage?(production) hide the buttons it
# would refuse.
module TeamPermissionsHelper
  # For an organization-wide page's create buttons: a manager of at least one
  # production can start something.
  def manages_any_production?
    return false unless Current.user
    return @manages_any_production if defined?(@manages_any_production)

    @manages_any_production = Current.user.managed_productions.exists?
  end
end
