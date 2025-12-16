# frozen_string_literal: true

class AuditionRequestVote < ApplicationRecord
  belongs_to :audition_request
  belongs_to :user

  enum :vote, { yes: 0, no: 1, maybe: 2 }

  validates :vote, presence: true
  validates :user_id, uniqueness: { scope: :audition_request_id, message: "has already voted on this sign-up" }
end
