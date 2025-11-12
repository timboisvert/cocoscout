class Cast < ApplicationRecord
  belongs_to :production
  has_and_belongs_to_many :people
  # Note: cast_assignment_stages are deleted via Production's before_destroy callback
  # to avoid foreign key constraint issues
  has_many :cast_assignment_stages

  validates :name, presence: true
end
