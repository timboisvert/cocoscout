class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :production_company

  validates :role, presence: true, inclusion: { in: %w[admin member talent] }
  validates :user_id, uniqueness: { scope: :production_company_id }
end
