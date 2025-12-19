# frozen_string_literal: true

class OrganizationRole < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  validates :company_role, presence: true, inclusion: { in: %w[manager viewer member] }
  validates :user_id, uniqueness: { scope: :organization_id }

  # Returns whether notifications are enabled for this organization role.
  # If explicitly set, returns that value.
  # Otherwise, returns a role-based default: true for managers, false for viewers/members.
  def notifications_enabled?
    return notifications_enabled unless notifications_enabled.nil?

    # Role-based default
    company_role == "manager"
  end
end
