class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :production_company

  validates :company_role, presence: true, inclusion: { in: %w[manager viewer none] }
  validates :user_id, uniqueness: { scope: :production_company_id }
end
