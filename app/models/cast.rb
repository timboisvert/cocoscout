class Cast < ApplicationRecord
  belongs_to :production
  has_and_belongs_to_many :people
  has_many :cast_assignment_stages, dependent: :destroy

  validates :name, presence: true
end
