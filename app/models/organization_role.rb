# frozen_string_literal: true

class OrganizationRole < ApplicationRecord
  belongs_to :user
  belongs_to :organization
  belongs_to :person, optional: true

  validates :company_role, presence: true, inclusion: { in: %w[manager viewer member] }
  validates :user_id, uniqueness: { scope: :organization_id }

  # Returns the person to display for this role
  # Uses the explicitly set person_id if available, otherwise falls back to user's primary person
  def display_person
    person || user.person
  end
end
