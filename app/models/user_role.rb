class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :production_company

  validates :role, presence: true, inclusion: { in: %w[manager viewer] }
  validates :user_id, uniqueness: { scope: :production_company_id }
end
