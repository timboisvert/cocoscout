class ProductionPermission < ApplicationRecord
  belongs_to :user
  belongs_to :production

  validates :role, presence: true, inclusion: { in: %w[manager viewer] }
  validates :user_id, uniqueness: { scope: :production_id }
end
