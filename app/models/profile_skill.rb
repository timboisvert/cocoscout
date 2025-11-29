class ProfileSkill < ApplicationRecord
  belongs_to :profileable, polymorphic: true

  # Validations
  validates :category, presence: true, length: { maximum: 50 }
  validates :skill_name, presence: true, length: { maximum: 50 }
  validates :skill_name, uniqueness: {
    scope: [ :profileable_type, :profileable_id, :category ],
    message: "has already been added to this category"
  }

  # Scopes
  default_scope { order(:category, :skill_name) }
  scope :by_category, ->(category) { where(category: category) }
end
