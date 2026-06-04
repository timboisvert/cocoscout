# frozen_string_literal: true

# Import Chicagoland open mics from the public Google Sheet maintained
# by the local comedy scene. The sheet groups mics by day-of-week
# sections, with header rows we ignore.
#
# Usage — fetch the live sheet directly (recommended):
#   bin/rails mics:import_chicago SHEET_URL="https://docs.google.com/spreadsheets/d/<ID>/edit?gid=<TAB>"
#   bin/rails mics:import_chicago SHEET_ID=<ID> GID=<TAB>
#
# Usage — local CSV file:
#   bin/rails mics:import_chicago CSV=/tmp/chicago_mics.csv
#   bin/rails mics:import_chicago                  # defaults to /tmp/chicago_mics.csv
require "csv"
require "net/http"
require "uri"

namespace :mics do
  # Fields whose changes we want to log to `mic_edits` so producers can
  # see what the sheet did. Excludes timestamps and IDs.
  TRACKED_FIELDS = %w[day_of_week starts_local_time signup_opens_at_text
                       format signup_method bucket_draw cost status].freeze

  desc "Import Chicagoland mics from the community Google Sheet (URL or CSV)."
  task import_chicago: [ :environment, :seed_chicago_hub ] do
    path = resolve_csv_path
    unless File.exist?(path)
      abort "CSV file not found at #{path}. Provide SHEET_URL=, SHEET_ID=+GID=, or CSV=<path>."
    end

    days = {
      "sunday" => 0, "monday" => 1, "tuesday" => 2, "wednesday" => 3,
      "thursday" => 4, "friday" => 5, "saturday" => 6
    }

    current_day = nil
    created   = 0
    updated   = 0
    preserved = 0
    skipped   = 0
    venues_created = 0
    chicago_hub = CityHub.find_by(slug: "chicago-il")
    abort "Run mics:seed_chicago_hub first." unless chicago_hub

    CSV.foreach(path, encoding: "bom|utf-8") do |row|
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

      # Match against a normalized form of the venue name so curly vs
      # straight apostrophes, trailing whitespace, or case drift don't
      # spawn a second venue row. Same for city.
      norm_name = venue_name.downcase.gsub(/[‘’']/, "").gsub(/\s+/, " ").strip
      norm_city = city.downcase.strip
      venue = Venue.where(state: state).find do |v|
        v.name.to_s.downcase.gsub(/[‘’']/, "").gsub(/\s+/, " ").strip == norm_name &&
          v.city.to_s.downcase.strip == norm_city
      end
      venue ||= Venue.new(name: venue_name, city: city, state: state)
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

      # Match the mic name with the same normalization as venues so
      # casing/punctuation drift doesn't dupe.
      norm_mic = mic_name.downcase.gsub(/[‘’']/, "").gsub(/\s+/, " ").strip
      mic = if venue.persisted?
        venue.mics.find { |m| m.name.to_s.downcase.gsub(/[‘’']/, "").gsub(/\s+/, " ").strip == norm_mic }
      end
      mic ||= Mic.new(name: mic_name, venue: venue)
      claimed = mic.persisted? && mic.mic_owners.any?
      old_attrs = mic.attributes.slice(*TRACKED_FIELDS).dup

      inferred_method, bucket = infer_signup_method(signup_notes)
      inferred_format         = infer_format(mic_name, signup_notes)

      if mic.new_record?
        # First sight — sheet is authoritative for everything.
        mic.day_of_week          = current_day
        mic.starts_local_time    = parse_time(start_time)
        mic.signup_opens_at_text = signup_notes.presence
        mic.format               = inferred_format
        mic.signup_method        = inferred_method if inferred_method
        mic.bucket_draw          = bucket
        mic.cost              ||= :free
        mic.status            ||= :active
        mic.last_verified_at    = Time.current
        created += 1
      elsif claimed
        # A producer (or captain) has claimed this — DON'T clobber the
        # curated fields. Only backfill anything still blank.
        mic.day_of_week          ||= current_day
        mic.starts_local_time    ||= parse_time(start_time)
        mic.signup_opens_at_text ||= signup_notes.presence
        mic.format               ||= inferred_format
        mic.signup_method        ||= inferred_method
        mic.bucket_draw            = bucket if mic.bucket_draw.nil?
        mic.cost                 ||= :free
        mic.status               ||= :active
        preserved += 1
      else
        # Unclaimed existing row — the sheet still wins.
        mic.day_of_week          = current_day
        mic.starts_local_time    = parse_time(start_time)
        mic.signup_opens_at_text = signup_notes.presence
        mic.format               = inferred_format
        mic.signup_method        = inferred_method if inferred_method
        mic.bucket_draw          = bucket
        mic.cost               ||= :free
        mic.status             ||= :active
        updated += 1
      end

      mic.save!

      # Audit any field that actually changed so the producer dashboard
      # shows where the new value came from.
      mic.attributes.slice(*TRACKED_FIELDS).each do |k, v|
        next if old_attrs[k].to_s == v.to_s
        mic.mic_edits.create!(source: :migration, field: k,
                              old_value: old_attrs[k].to_s, new_value: v.to_s,
                              note: "Chicago sheet import")
      end

      extract_links_from_notes(mic, signup_notes)
    rescue => e
      warn "  ! failed row: #{row.inspect} → #{e.message}"
      skipped += 1
    end

    puts "✓ Chicago import complete."
    puts "  mics    — created: #{created}, updated: #{updated}, preserved (claimed): #{preserved}, skipped: #{skipped}"
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

  # Returns a path to a CSV file on disk. Either the user already gave us
  # one via CSV=..., or we derive a Google-Sheets CSV-export URL from
  # SHEET_URL / SHEET_ID(+GID) and download it to /tmp.
  def self.resolve_csv_path
    return ENV["CSV"] if ENV["CSV"].present?

    sheet_id, gid = extract_sheet_id_and_gid
    if sheet_id
      out = "/tmp/chicago_mics-#{sheet_id}-#{gid || 0}.csv"
      download_sheet_as_csv(sheet_id, gid, out)
      return out
    end

    "/tmp/chicago_mics.csv"
  end

  def self.extract_sheet_id_and_gid
    if (id = ENV["SHEET_ID"]).present?
      return [ id, ENV["GID"].presence || "0" ]
    end

    url = ENV["SHEET_URL"].to_s
    return [ nil, nil ] if url.blank?

    id_match = url.match(%r{/spreadsheets/d/([A-Za-z0-9_-]+)})
    gid_match = url.match(/gid=([0-9]+)/)
    return [ nil, nil ] unless id_match
    [ id_match[1], gid_match ? gid_match[1] : "0" ]
  end

  def self.download_sheet_as_csv(sheet_id, gid, out_path)
    # IMPORTANT: use the Visualization API (`gviz/tq?tqx=out:csv`) instead
    # of the plain `export?format=csv` endpoint. The export endpoint
    # dumps every row in the underlying data including ones the sheet
    # owner has explicitly hidden — meaning entries the community has
    # taken down still get imported. The gviz endpoint respects hidden
    # rows the way a human viewing the sheet would.
    export_url = "https://docs.google.com/spreadsheets/d/#{sheet_id}/gviz/tq?tqx=out:csv&gid=#{gid || 0}"
    puts "→ fetching #{export_url}"
    uri = URI.parse(export_url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      # Sheets returns a 307 redirect to the actual CSV. Follow up to 3
      # hops so we don't get stuck on the redirect chain.
      req = Net::HTTP::Get.new(uri)
      res = http.request(req)
      hops = 0
      while res.is_a?(Net::HTTPRedirection) && hops < 3
        new_uri = URI.parse(res["Location"])
        new_uri = uri.merge(new_uri) if new_uri.host.nil?
        res = Net::HTTP.start(new_uri.host, new_uri.port, use_ssl: new_uri.scheme == "https") do |h2|
          h2.request(Net::HTTP::Get.new(new_uri))
        end
        hops += 1
      end
      res
    end

    unless response.is_a?(Net::HTTPSuccess)
      abort "Failed to fetch sheet (#{response.code}). Make sure the sheet is shared with anyone-with-the-link viewer access."
    end

    # Write in binary mode — Net::HTTP returns ASCII-8BIT bytes, and the
    # sheet contains UTF-8 multi-byte characters (curly quotes, em
    # dashes). Plain `File.write` would try to transcode and explode on
    # \xC3-prefixed bytes. CSV.foreach below opens the file fresh and
    # decodes it correctly.
    File.binwrite(out_path, response.body)
    puts "  saved #{response.body.bytesize} bytes → #{out_path}"
  end
end
