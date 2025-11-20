class Cast < ApplicationRecord
  belongs_to :production
  has_many :cast_memberships, dependent: :destroy
  has_many :people, through: :cast_memberships, source: :castable, source_type: 'Person'
  has_many :groups, through: :cast_memberships, source: :castable, source_type: 'Group'
  # Note: cast_assignment_stages are deleted via Production's before_destroy callback
  # to avoid foreign key constraint issues
  has_many :cast_assignment_stages

  validates :name, presence: true

  # Helper method to get all castables (both people and groups)
  def castables
    cast_memberships.includes(:castable).map(&:castable)
  end
end
