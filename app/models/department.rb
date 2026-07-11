# frozen_string_literal: true

# A named part of an organization's workforce (e.g. Front of House, Box Office,
# Tech). Staff members are tagged with a department by name.
class Department < ApplicationRecord
  belongs_to :organization

  validates :name, presence: true, length: { maximum: 100 },
                   uniqueness: { scope: :organization_id, case_sensitive: false }

  scope :ordered, -> { order(:position, :name) }
end
