# frozen_string_literal: true

module DurationHelper
  # Formats a number of minutes as a human-readable duration.
  # Examples: 150 => "2 hours 30 minutes", 60 => "1 hour", 45 => "45 minutes", 0 => "0 minutes"
  def format_duration(minutes)
    return nil if minutes.blank?

    minutes = minutes.to_i
    hours = minutes / 60
    mins = minutes % 60

    parts = []
    parts << "#{hours} #{'hour'.pluralize(hours)}" if hours.positive?
    parts << "#{mins} #{'minute'.pluralize(mins)}" if mins.positive?
    parts << "0 minutes" if parts.empty?
    parts.join(" ")
  end
end
