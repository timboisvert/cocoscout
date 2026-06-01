# frozen_string_literal: true

# A user's opt-in to be pinged before this Mic's sign-up opens. The
# scheduler computes the next target time and a delivery job mails the
# user when it elapses. Channels: email (v1), web_push, native (later).
class MicSignupAlert < ApplicationRecord
  belongs_to :mic
  belongs_to :user

  validates :user_id, uniqueness: { scope: :mic_id }

  scope :active, -> { where(active: true) }
  scope :due, ->(at = Time.current) {
    active.where("next_target_at IS NOT NULL AND next_target_at <= ?", at)
  }

  # Recompute the next time we need to fire this alert. Returns the
  # computed target (or nil if there's no upcoming opens-at).
  def recompute_target!
    target = compute_target_at
    update!(next_target_at: target)
    target
  end

  private

  def compute_target_at
    info = mic.signup_info
    return nil unless info

    opens_at = info[:opens_at]
    if opens_at.blank? && info[:opens_at_text].present?
      # Fallback: 30 min before the next occurrence start.
      next_occ = mic.next_occurrences(limit: 1).first
      return nil unless next_occ
      opens_at = next_occ[:starts_at] - 30.minutes
    end
    return nil if opens_at.blank?

    target = opens_at - lead_time_minutes.minutes
    return nil if target < Time.current
    target
  end
end
