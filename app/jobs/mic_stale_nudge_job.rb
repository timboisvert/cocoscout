# frozen_string_literal: true

# Daily: mark producers whose mics haven't been verified in >90 days.
# Logs a MicEdit row per stale mic. Mailers would be plugged in here
# when we want producer email nudges.
class MicStaleNudgeJob < ApplicationJob
  queue_as :background

  STALE_THRESHOLD = 90.days
  DORMANT_THRESHOLD = 180.days

  def perform
    Mic.active.where("last_verified_at < ? OR last_verified_at IS NULL", STALE_THRESHOLD.ago).find_each do |mic|
      MicEdit.create!(mic_id: mic.id, source: :system, field: "stale", new_value: "nudge",
                      note: "Auto-flagged: not verified in 90 days")
    end

    Mic.active.where("last_verified_at < ?", DORMANT_THRESHOLD.ago).find_each do |mic|
      mic.update!(status: :dormant)
      MicEdit.create!(mic_id: mic.id, source: :system, field: "status",
                      new_value: "dormant", note: "Auto-dormant: 180 days un-verified")
    end
  end
end
