# frozen_string_literal: true

class MessagePollVote < ApplicationRecord
  belongs_to :message_poll_option
  belongs_to :user

  validates :user_id, uniqueness: { scope: :message_poll_option_id, message: "already voted for this option" }
  validate :max_votes_not_exceeded, on: :create

  private

  def max_votes_not_exceeded
    poll = message_poll_option&.message_poll
    return unless poll

    current_votes = poll.user_vote_option_ids(user).size
    if current_votes >= poll.max_votes
      errors.add(:base, "You have already used all your votes (max #{poll.max_votes})")
    end
  end
end
