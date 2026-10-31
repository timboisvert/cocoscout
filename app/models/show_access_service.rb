# frozen_string_literal: true

# An access service at one performance (accessibility plan §2): interpreted,
# captioned, audio described, relaxed, a touch tour, masks required; with a
# detail (the sign language, the caption type, the tour time).
class ShowAccessService < ApplicationRecord
  SERVICES = %w[interpreted captioned audio_described relaxed touch_tour masked].freeze
  LABELS = { "interpreted" => "Interpreted", "captioned" => "Captioned", "audio_described" => "Audio described", "relaxed" => "Relaxed performance",
             "touch_tour" => "Touch tour", "masked" => "Masks required" }.freeze
  HINTS = { "interpreted" => "Which sign language: ASL, BSL, Auslan…", "captioned" => "Open captions, a caption app…", "audio_described" => "Headsets at the door, an app…",
            "relaxed" => "House lights up, come and go freely…", "touch_tour" => "When, and where to meet", "masked" => "Which performances, what's provided" }.freeze

  belongs_to :show

  validates :service, inclusion: { in: SERVICES }, uniqueness: { scope: :show_id }
  validates :detail, length: { maximum: 200 }

  def label = LABELS.fetch(service)
  def words = detail.present? ? "#{label} (#{detail})" : label
end
