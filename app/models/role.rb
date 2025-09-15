class Role < ApplicationRecord
  belongs_to :production

  has_many :show_person_role_assignments, dependent: :destroy
  has_many :shows, through: :show_person_role_assignments

  validates :name, presence: true
end
