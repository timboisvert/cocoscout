# frozen_string_literal: true

module Manage
  module ShowsHelper
    RECURRENCE_PATTERNS = [
      [ "Daily", "daily" ],
      [ "Weekly", "weekly" ],
      [ "Every other week", "biweekly" ],
      [ "Monthly (same date)", "monthly_date" ],
      [ "Monthly (same weekday)", "monthly_week" ]
    ].freeze

    # "Every Friday", "Every other Friday", "Monthly on the 2nd Friday" — the
    # series' rhythm in words, anchored on one of its events. Falls back to the
    # raw pattern name when there's nothing to anchor on.
    def series_pattern_phrase(pattern, anchor)
      return pattern.to_s.tr("_", " ").capitalize if anchor.nil? || anchor.date_and_time.nil?

      t = anchor.date_and_time
      day = t.strftime("%A")
      case pattern.to_s
      when "daily"        then "Every day"
      when "weekly"       then "Every #{day}"
      when "biweekly"     then "Every other #{day}"
      when "monthly_date" then "Monthly on the #{t.day.ordinalize}"
      when "monthly_week"
        ordinal = %w[first second third fourth fifth][(t.day - 1) / 7]
        "Monthly on the #{ordinal} #{day}"
      else pattern.to_s.tr("_", " ").capitalize.presence || "Repeating"
      end
    end
  end
end
