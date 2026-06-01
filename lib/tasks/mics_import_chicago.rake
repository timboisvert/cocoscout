# frozen_string_literal: true

# Import Chicagoland open mics from a CSV pulled from the public Google
# Sheet maintained by the local comedy scene. The sheet groups mics by
# day-of-week sections, with header rows we ignore.
#
# Usage:
#   bin/rails mics:import_chicago
#   bin/rails mics:import_chicago CSV=/tmp/chicago_mics.csv
require "csv"

namespace :mics do
  desc "Import Chicagoland mics from the community Google Sheet CSV."
  task import_chicago: :environment do
    path = ENV["CSV"] || "/tmp/chicago_mics.csv"
    unless File.exist?(path)
      abort "CSV file not found at #{path}. Download the sheet to that path first."
    end

    days = {
      "sunday" => 0, "monday" => 1, "tuesday" => 2, "wednesday" => 3,
      "thursday" => 4, "friday" => 5, "saturday" => 6
    }

    current_day = nil
    created = 0
    updated = 0
    skipped = 0
    venues_created = 0
    chicago_hub = CityHub.find_by(slug: "chicago-il")
    abort "Run mics:seed_chicago_hub first." unless chicago_hub

    CSV.foreach(path) do |row|
      next if row.compact.empty?

      first = row[0].to_s.strip
      next if first.blank?
      next if first.start_with?("Suburban", "Resource Links", "Upcoming One-Off", "Map Link")
      next if row[0].to_s.start_with?("http")

      # Day-of-week section header (e.g. "Tuesday")?
      day_key = first.downcase
      if days.key?(day_key)
        current_day = days[day_key]
        next
      end

      # Column header row?
      next if first == "Mic Name"

      next unless current_day # rows before the first day header

      mic_name      = first
      venue_name    = row[1].to_s.strip
      address_blob  = row[2].to_s.strip
      signup_notes  = row[3].to_s.strip
      start_time    = row[4].to_s.strip

      next if mic_name.blank? || venue_name.blank?

      city, state, postal = parse_address(address_blob)
      city  ||= "Chicago"
      state ||= "IL"

      venue = Venue.find_or_initialize_by(name: venue_name, city: city, state: state)
      venue.address1    = address1_from(address_blob)
      venue.postal_code = postal if postal.present?
      venue.timezone  ||= "America/Chicago"
      venue.country   ||= "US"
      # Every venue from this sheet rolls up to the Chicago hub. The
      # venue keeps its real city for maps + distance; the hub_id
      # determines which listing page it appears on.
      venue.city_hub  ||= chicago_hub
      if venue.new_record?
        venues_created += 1
      end
      venue.save!

      mic = Mic.find_or_initialize_by(name: mic_name, venue: venue)
      mic.day_of_week       = current_day
      mic.starts_local_time = parse_time(start_time)
      mic.signup_opens_at_text = signup_notes.presence
      mic.format            = infer_format(mic_name, signup_notes)
      inferred_method, bucket = infer_signup_method(signup_notes)
      mic.signup_method     = inferred_method if inferred_method
      mic.bucket_draw       = bucket
      mic.cost            ||= :free
      mic.status          ||= :active
      mic.last_verified_at = Time.current if mic.new_record?
      if mic.new_record?
        created += 1
      else
        updated += 1
      end
      mic.save!

      extract_links_from_notes(mic, signup_notes)
    rescue => e
      warn "  ! failed row: #{row.inspect} → #{e.message}"
      skipped += 1
    end

    puts "✓ Chicago import complete."
    puts "  mics    — created: #{created}, updated: #{updated}, skipped: #{skipped}"
    puts "  venues  — created: #{venues_created}"
  end

  def self.parse_address(blob)
    return [ nil, nil, nil ] if blob.blank?
    # Try: "..., City, IL 60601" or "..., City, IL"
    if (m = blob.match(/,\s*([A-Za-z .'\-]+?),\s*([A-Z]{2})(?:\s+(\d{5}))?\s*$/))
      [ m[1].strip, m[2], m[3] ]
    elsif (m = blob.match(/,\s*([A-Za-z .'\-]+?)\s+([A-Z]{2})\s+(\d{5})/))
      [ m[1].strip, m[2], m[3] ]
    else
      [ nil, nil, nil ]
    end
  end

  def self.address1_from(blob)
    # Everything before the first comma is the street address.
    blob.to_s.split(",").first&.strip
  end

  def self.parse_time(str)
    return nil if str.blank?
    Time.zone.parse(str)
  rescue ArgumentError
    nil
  end

  def self.infer_format(name, notes)
    n = "#{name} #{notes}".downcase
    return :open_stage if n.match?(/open stage|sketch|improv|variety/)
    return :music      if n.match?(/music|musician|musical|jam session/)
    return :poetry     if n.match?(/poetry|spoken word/)
    :standup
  end

  EMAIL_TLDS = %w[com net org io co edu gov us].freeze

  def self.extract_links_from_notes(mic, notes)
    return if notes.blank?

    # Instagram handles like "@liaberman3" or "@showpen.mic". Skip
    # anything that's actually an email address (preceded by a word
    # char) or that ends in a TLD like .com.
    notes.scan(/(?<![A-Za-z0-9])@([A-Za-z0-9_.]+)/) do |(raw)|
      handle = raw.sub(/[.]+$/, "") # strip trailing dots
      next if handle.length < 2
      next if EMAIL_TLDS.include?(handle.split(".").last&.downcase)
      url = "https://instagram.com/#{handle}"
      next if mic.mic_links.exists?(url: url)
      mic.mic_links.create!(link_type: :instagram, url: url, label: "@#{handle}")
    end

    # Plain http(s) URLs — only the four social types we support.
    notes.scan(%r{https?://[^\s,)]+}) do |url|
      cleaned = url.gsub(/[.,)]+$/, "")
      next if mic.mic_links.exists?(url: cleaned)
      type =
        if cleaned.include?("instagram.com") then :instagram
        elsif cleaned.include?("tiktok.com")    then :tiktok
        elsif cleaned.match?(/x\.com|twitter\.com/) then :x_twitter
        else :website
        end
      mic.mic_links.create!(link_type: type, url: cleaned)
    end
  end

  # Returns [signup_method, bucket_draw_bool]. Most Chicago mics still
  # use in-person sign-up — assume that as the default, and only mark
  # online when the notes explicitly say so.
  def self.infer_signup_method(notes)
    n = notes.to_s.downcase
    bucket = n.match?(/\bbucket(\s+draw)?\b|random draw|drawn from a bucket/i)

    online_signal      = n.match?(/online sign[\s-]?up|sign[\s-]?up online|signup online|online lottery|google form|google sheet|sign up online|fb (group|post)|facebook (group|post)/i)
    in_person_explicit = n.match?(/in[\s-]?person|walk[\s-]?up|at the box office/i)

    method =
      if online_signal && in_person_explicit then :online_and_in_person
      elsif online_signal                    then :online
      else                                         :in_person  # default
      end

    [ method, bucket ]
  end
end
