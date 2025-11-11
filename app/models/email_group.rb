class EmailGroup < ApplicationRecord
  belongs_to :call_to_audition

  validates :group_id, presence: true, uniqueness: { scope: :call_to_audition_id }
  validates :name, presence: true, length: { maximum: 30 }
end
