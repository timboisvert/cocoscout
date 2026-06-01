# frozen_string_literal: true

# Seeding + maintenance tasks for the Mics Finder.
namespace :mics do
  desc "Seed the Chicago CityHub row (idempotent) so the city graduates to a curated hub."
  task seed_chicago_hub: :environment do
    hub = CityHub.find_or_initialize_by(slug: "chicago-il")
    hub.assign_attributes(
      name: "Chicago",
      state: "IL",
      timezone: "America/Chicago",
      default_radius_miles: 25,
      intro_markdown: <<~TXT.strip,
        Chicago has the deepest open-mic culture in the country — Tuesday bucket draws, Wednesday pre-signups, Sunday late-nights. This page is updated by the people who actually run the rooms.
      TXT
      status: :active
    )
    hub.save!
    puts "✓ Chicago hub: #{hub.slug} (status: #{hub.status})"
  end

  desc "Seed a small starter set of Chicago mics for early testing (idempotent)."
  task seed_chicago_starter: :environment do
    rows = [
      { venue: "Cafe Mustache",       neighborhood: "Logan Square",  day: 2, time: "20:00", format: :standup, name: "Mustache Mic" },
      { venue: "Beat Kitchen",        neighborhood: "Roscoe Village", day: 0, time: "19:30", format: :standup, name: "Beat Kitchen Open Mic" },
      { venue: "The Lincoln Lodge",   neighborhood: "Lincoln Square", day: 1, time: "21:00", format: :standup, name: "Lincoln Lodge Mic" },
      { venue: "Subterranean",        neighborhood: "Wicker Park",   day: 3, time: "20:00", format: :music,    name: "Sub-T Open Mic" },
      { venue: "Crowley's Bar",       neighborhood: "Lincoln Park",  day: 6, time: "22:30", format: :standup, name: "Crowley's Late Mic" }
    ]
    rows.each do |r|
      venue = Venue.find_or_create_by!(name: r[:venue], city: "Chicago", state: "IL") do |v|
        v.neighborhood = r[:neighborhood]
        v.timezone = "America/Chicago"
      end
      Mic.find_or_create_by!(name: r[:name], venue: venue) do |m|
        m.day_of_week = r[:day]
        m.starts_local_time = Time.zone.parse(r[:time])
        m.format = r[:format]
        m.signup_method = :bucket_draw
        m.cost = :free
        m.status = :active
        m.last_verified_at = Time.current
      end
    end
    puts "✓ Seeded #{rows.size} starter Chicago mics."
  end

  desc "Run the daily stale-mic nudge synchronously (for testing)."
  task stale_nudge: :environment do
    MicStaleNudgeJob.perform_now
    puts "✓ Stale nudge run."
  end
end
