# frozen_string_literal: true

class ProductionPermission < ApplicationRecord
  belongs_to :user
  belongs_to :production

  validates :role, presence: true, inclusion: { in: %w[manager viewer] }
  validates :user_id, uniqueness: { scope: :production_id }

  # Returns whether notifications are enabled for this permission.
  # If explicitly set, returns that value.
  # Otherwise, returns a role-based default: true for managers, false for viewers.
  def notifications_enabled?
    return notifications_enabled unless notifications_enabled.nil?

    # Role-based default
    role == "manager"
  end
end
