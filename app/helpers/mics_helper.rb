# frozen_string_literal: true

# View helpers for the public Open Mic Finder — SEO blocks (meta + og +
# twitter + JSON-LD), small format/display helpers, etc.
module MicsHelper
  DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  DAY_NAMES_SHORT = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

  def mics_day_name(day)
    DAY_NAMES[day.to_i] if day.present?
  end

  def mics_day_short(day)
    DAY_NAMES_SHORT[day.to_i] if day.present?
  end

  # Render the page's `<title>` AND `<meta name="description">` plus a full
  # OG/Twitter pack. Call from a view with `mics_seo title: "...", description: "..."`.
  def mics_seo(title:, description:, canonical_url: nil, og_image_url: nil)
    canonical_url ||= request.original_url
    og_image_url  ||= asset_url_safe("mics/og-default.png")
    content_for :title, title
    content_for :head do
      tags = []
      tags << tag.meta(name: "description", content: description)
      tags << tag.link(rel: "canonical", href: canonical_url)
      # OpenGraph
      tags << tag.meta(property: "og:title",       content: title)
      tags << tag.meta(property: "og:description", content: description)
      tags << tag.meta(property: "og:url",         content: canonical_url)
      tags << tag.meta(property: "og:type",        content: "website")
      tags << tag.meta(property: "og:site_name",   content: "Find a Mic")
      tags << tag.meta(property: "og:image",       content: og_image_url) if og_image_url
      # Twitter
      tags << tag.meta(name: "twitter:card",        content: "summary_large_image")
      tags << tag.meta(name: "twitter:title",       content: title)
      tags << tag.meta(name: "twitter:description", content: description)
      tags << tag.meta(name: "twitter:image",       content: og_image_url) if og_image_url
      safe_join(tags, "\n".html_safe)
    end
  end

  def asset_url_safe(path)
    asset_path(path)
  rescue StandardError
    nil
  end

  def mics_jsonld(payload)
    content_tag(:script, raw(payload.to_json), type: "application/ld+json")
  end

  def mics_breadcrumbs_jsonld(items)
    mics_jsonld(
      "@context": "https://schema.org",
      "@type":    "BreadcrumbList",
      "itemListElement": items.each_with_index.map do |(name, url), i|
        { "@type": "ListItem", position: i + 1, name: name, item: url }
      end
    )
  end

  # JSON-LD `Event` payload for one mic occurrence.
  def mic_event_jsonld(mic, occurrence)
    starts_at = occurrence[:starts_at]
    ends_at   = mic.spot_length_minutes ? starts_at + (mic.spot_length_minutes * 60) : nil
    status =
      case occurrence[:mic_status]
      when "cancelled" then "https://schema.org/EventCancelled"
      when "online_only" then "https://schema.org/EventMovedOnline"
      else "https://schema.org/EventScheduled"
      end
    venue = mic.venue
    {
      "@context": "https://schema.org",
      "@type": "Event",
      name: mic.name,
      startDate: starts_at.iso8601,
      endDate: ends_at&.iso8601,
      eventStatus: status,
      eventAttendanceMode: "https://schema.org/OfflineEventAttendanceMode",
      description: mic.blurb.presence,
      url: mics_detail_url(mic.slug),
      location: {
        "@type": "Place",
        name: venue.name,
        address: {
          "@type": "PostalAddress",
          streetAddress: venue.address1,
          addressLocality: venue.city,
          addressRegion: venue.state,
          postalCode: venue.postal_code,
          addressCountry: venue.country
        }
      }
    }.compact
  end

  # Human-readable summary of a mic's schedule, e.g. "Every Tuesday at 8:00 PM"
  # or "1st Tuesday of every month at 8:00 PM".
  def mics_schedule_label(mic)
    return nil unless mic.starts_local_time
    day = mics_day_name(mic.day_of_week)
    time = mic.starts_local_time.strftime("%-l:%M %p")
    base = case mic.recurrence_pattern.to_s
    when "biweekly"             then "Every other #{day}"
    when "monthly_nth_weekday"
      n = mic.recurrence_nth_week
      ord = n == -1 ? "Last" : ord_for(n)
      "#{ord} #{day} of every month"
    when "monthly_nth_weekdays"
      weeks = Array(mic.recurrence_nth_weeks).map(&:to_i).reject(&:zero?).uniq.sort_by { |n| n == -1 ? 99 : n }
      return nil if weeks.empty?
      ords = weeks.map { |n| n == -1 ? "Last" : ord_for(n) }
      "#{ords.to_sentence(two_words_connector: " & ", last_word_connector: ", & ")} #{day} of every month"
    when "monthly_day_of_month"
      "Day #{mic.recurrence_day_of_month} of every month"
    else
      day ? "Every #{day}" : nil
    end
    base && "#{base} at #{time}"
  end

  def ord_for(n)
    %w[0th 1st 2nd 3rd 4th 5th][n.to_i] || "#{n}th"
  end

  def mics_format_label(value)
    case value.to_s
    when "standup"    then "Standup"
    when "music"      then "Music"
    when "poetry"     then "Poetry"
    when "open_stage" then "Open Stage"
    else value.to_s.humanize
    end
  end

  def mics_signup_method_label(value)
    case value.to_s
    when "online"                then "Online"
    when "in_person"             then "In person"
    when "online_and_in_person"  then "Online + in person"
    else value.to_s.humanize
    end
  end

  def mics_cost_label(mic)
    case mic.cost
    when "free" then "Free"
    when "drink_minimum"
      mic.drink_minimum_amount_cents.present? ? "Drink minimum ($#{(mic.drink_minimum_amount_cents / 100.0).round(2)})" : "Drink minimum"
    when "pay_to_perform"
      mic.cover_amount_cents.present? ? "Pay $#{(mic.cover_amount_cents / 100.0).round(2)}" : "Pay-to-perform"
    when "pay_pass_the_hat" then "Pass-the-hat"
    end
  end

  # Appends the given params to a path, preserving an existing query.
  def mics_with_qp(path, qp)
    return path if qp.blank?
    sep = path.include?("?") ? "&" : "?"
    "#{path}#{sep}#{qp.to_query}"
  end

  # Default date input value: the mic's next upcoming occurrence date.
  def next_upcoming_date_for(mic)
    occ = mic.next_occurrences(limit: 1).first
    (occ ? occ[:starts_at].to_date : Date.current).iso8601
  end

  # Formats a `signup_opens_at_text` value (stored as "HH:MM") into the
  # human "7:30 PM" form for public display. Falls back to the raw value
  # if it's not a parseable time — old free-text entries still render.
  def mics_signup_opens_label(text)
    return nil if text.blank?
    if text.match?(/\A\d{1,2}:\d{2}\z/)
      Time.zone.parse(text).strftime("%-l:%M %p")
    else
      text
    end
  rescue ArgumentError, TZInfo::AmbiguousTime
    text
  end

  def mics_time_label(time)
    return nil if time.blank?
    if time.to_date == Date.current
      time.strftime("%-l:%M %p")
    elsif time > Time.current.beginning_of_year
      time.strftime("%a %b %-d %-l:%M %p")
    else
      time.strftime("%b %-d, %Y %-l:%M %p")
    end
  end
end
