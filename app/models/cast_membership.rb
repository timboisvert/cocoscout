class CastMembership < ApplicationRecord
  belongs_to :cast
  belongs_to :castable, polymorphic: true

  validates :cast, presence: true
  validates :castable, presence: true
  validates :castable_id, uniqueness: { scope: [:cast_id, :castable_type], message: "is already in this cast" }
end
