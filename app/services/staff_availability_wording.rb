# frozen_string_literal: true

# How a StaffAvailabilityResolver::Verdict reads to a manager: a short badge
# for a person card, and a sentence for the collision modal and the flash.
# Naming the reason and the amount is what makes a "partly free" warning
# useful rather than noise: "Free from 8:30 PM, misses the first 1h 30m
# (their usual Friday)".
module StaffAvailabilityWording
  module_function

  # nil when there's nothing to say (free).
  def badge(verdict)
    case verdict.status
    when :blocked then "Unavailable"
    when :partial
      if verdict.free_from then "Free from #{clock(verdict.free_from)}"
      elsif verdict.free_until then "Free until #{clock(verdict.free_until)}"
      else "Free for part of it"
      end
    when :unknown then "Hasn't said"
    end
  end

  def detail(verdict)
    reason = verdict.reasons.first && " (#{reason_for(verdict.reasons.first)})"
    case verdict.status
    when :blocked
      "Can't work then#{reason}."
    when :partial
      missed = verdict.total_minutes - verdict.available_minutes
      span =
        if verdict.free_from && !verdict.free_until then "the first #{duration(missed)}"
        elsif verdict.free_until && !verdict.free_from then "the last #{duration(missed)}"
        else duration(missed)
        end
      "#{badge(verdict)}, misses #{span}#{reason}."
    when :unknown
      "Hasn't said when they can work."
    end
  end

  # What decided it, in the words the person set it in.
  def reason_for(entry)
    if entry.weekly?
      "their usual #{Date::DAYNAMES[entry.day_of_week]}"
    elsif entry.note.present?
      "“#{entry.note}”"
    elsif entry.starts_on == entry.ends_on
      "an exception for #{entry.starts_on.strftime('%b %-d')}"
    else
      "an exception for #{entry.starts_on.strftime('%b %-d')} – #{entry.ends_on.strftime('%b %-d')}"
    end
  end

  def clock(time)
    time.strftime(time.min.zero? ? "%-l %p" : "%-l:%M %p")
  end

  # 90 → "1h 30m", 60 → "1h", 45 → "45m".
  def duration(minutes)
    hours, mins = minutes.to_i.divmod(60)
    [ (hours.positive? ? "#{hours}h" : nil), (mins.positive? ? "#{mins}m" : nil) ].compact.join(" ").presence || "0m"
  end
end
