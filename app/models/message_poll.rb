# frozen_string_literal: true

class MessagePoll < ApplicationRecord
  belongs_to :message
  has_many :message_poll_options, -> { order(:position) }, dependent: :destroy
  has_many :message_poll_votes, through: :message_poll_options

  accepts_nested_attributes_for :message_poll_options, allow_destroy: true,
    reject_if: proc { |attrs| attrs["text"].blank? }

  validates :question, presence: true
  validates :max_votes, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
  validate :at_least_two_options

  # Check if a user has voted
  def voted_by?(user)
    message_poll_votes.exists?(user: user)
  end

  # Get all option IDs a user voted for
  def user_vote_option_ids(user)
    message_poll_votes.where(user: user).pluck(:message_poll_option_id)
  end

  # Total unique voters
  def total_voters
    message_poll_votes.select(:user_id).distinct.count
  end

  # Whether the poll is still accepting votes
  def accepting_votes?
    !closed? && (closes_at.nil? || closes_at > Time.current)
  end

  # Close the poll
  def close!
    update!(closed: true)
  end

  # Whether a user can vote (hasn't exceeded max_votes)
  def can_vote?(user)
    return false unless accepting_votes?
    user_vote_option_ids(user).size < max_votes
  end

  # Whether the user is the poll creator (message sender)
  def created_by?(user)
    message.sender_type == "User" && message.sender_id == user.id
  end

  private

  def at_least_two_options
    live_options = message_poll_options.reject(&:marked_for_destruction?)
    if live_options.size < 2
      errors.add(:base, "Poll must have at least 2 options")
    end
  end
end
