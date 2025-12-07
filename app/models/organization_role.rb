# frozen_string_literal: true

class OrganizationRole < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  validates :company_role, presence: true, inclusion: { in: %w[manager viewer none] }
  validates :user_id, uniqueness: { scope: :organization_id }
end
