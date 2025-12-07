# frozen_string_literal: true

class EmailGroup < ApplicationRecord
  belongs_to :audition_cycle

  validates :group_id, presence: true, uniqueness: { scope: :audition_cycle_id }
  validates :name, presence: true, length: { maximum: 30 }
end
