# frozen_string_literal: true

class AuditionVote < ApplicationRecord
  belongs_to :audition
  belongs_to :user

  enum :vote, { yes: 0, no: 1, maybe: 2 }

  validates :vote, presence: true
  validates :user_id, uniqueness: { scope: :audition_id, message: "has already voted on this audition" }
end
