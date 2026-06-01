# frozen_string_literal: true

# A dispute against current producer(s) of a Mic. Open challenges hold
# open for 72 hours awaiting response from the current lead producer.
class MicChallenge < ApplicationRecord
  belongs_to :mic
  belongs_to :challenger, class_name: "User", foreign_key: :challenger_user_id
  belongs_to :target, class_name: "User", foreign_key: :target_user_id, optional: true
  belongs_to :adjudicator, class_name: "User", foreign_key: :adjudicator_user_id, optional: true

  enum :status, {
    pending: 0,
    replaced: 1,
    co_produce: 2,
    dismissed: 3,
    needs_info: 4
  }, prefix: :status

  RESPONSE_WINDOW = 72.hours

  def response_due_at
    created_at + RESPONSE_WINDOW
  end

  def response_overdue?
    status_pending? && Time.current > response_due_at
  end
end
