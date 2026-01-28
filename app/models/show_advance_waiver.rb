# frozen_string_literal: true

class ShowAdvanceWaiver < ApplicationRecord
  REASONS = %w[no_advances_this_show advance_carried_forward performer_declined other].freeze

  belongs_to :show
  belongs_to :person
  belongs_to :waived_by, class_name: "User"

  validates :reason, inclusion: { in: REASONS }
  validates :person_id, uniqueness: { scope: :show_id, message: "already has a waiver for this show" }
  validates :notes, presence: true, if: -> { reason == "other" }

  scope :for_show, ->(show) { where(show: show) }

  def self.reason_label(reason)
    case reason
    when "no_advances_this_show"
      "No advances for this show"
    when "advance_carried_forward"
      "Advance carried forward from previous show"
    when "performer_declined"
      "Performer declined advance"
    when "other"
      "Other"
    else
      reason.humanize
    end
  end

  def reason_label
    self.class.reason_label(reason)
  end
end
