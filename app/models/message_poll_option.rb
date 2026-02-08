# frozen_string_literal: true

class MessagePollOption < ApplicationRecord
  belongs_to :message_poll
  has_many :message_poll_votes, dependent: :destroy

  validates :text, presence: true

  # Vote count for this option
  def votes_count
    message_poll_votes.size
  end

  # Percentage of total voters who chose this option
  def vote_percentage(total_voters)
    return 0 if total_voters.zero?
    ((votes_count.to_f / total_voters) * 100).round
  end

  # Whether a specific user voted for this option
  def voted_by?(user)
    message_poll_votes.any? { |v| v.user_id == user.id }
  end
end
