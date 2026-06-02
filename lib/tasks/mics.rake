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

  desc "Run the daily stale-mic nudge synchronously (for testing)."
  task stale_nudge: :environment do
    MicStaleNudgeJob.perform_now
    puts "✓ Stale nudge run."
  end
end
