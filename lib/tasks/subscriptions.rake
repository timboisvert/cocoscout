# frozen_string_literal: true

namespace :subscriptions do
  desc "Comp Pro (indefinitely) for orgs already over the Producer plan's event or production limits. Dry-run by default; pass EXECUTE=1 to apply."
  task backfill_comps: :environment do
    execute = ENV["EXECUTE"] == "1"
    event_limit = Organization::FREE_MONTHLY_EVENT_LIMIT
    production_limit = Organization::FREE_PRODUCTION_LIMIT
    window_start = 12.months.ago.beginning_of_month
    window_end = 6.months.from_now.end_of_month

    puts(execute ? "Running (EXECUTE=1) — will comp over-limit orgs." : "DRY RUN — pass EXECUTE=1 to apply.")
    puts "Producer limits: #{event_limit} events/month, #{production_limit} production(s). " \
         "Events window #{window_start.to_date} .. #{window_end.to_date}.\n\n"

    comped = 0
    Organization.find_each do |org|
      next if org.comped_indefinitely?

      reasons = []

      # Max non-canceled events in any single calendar month within the window.
      counts_by_month = Show
        .where(production_id: org.productions.select(:id))
        .where(canceled: false)
        .where(date_and_time: window_start..window_end)
        .pluck(:date_and_time)
        .group_by { |dt| dt.strftime("%Y-%m") }
        .transform_values(&:count)

      peak_month, peak = counts_by_month.max_by { |_, count| count }
      reasons << "peak #{peak} events in #{peak_month}" if peak && peak > event_limit

      # Active, schedulable (non-course) productions.
      production_count = org.productions_counting_toward_limit.count
      reasons << "#{production_count} productions" if production_count > production_limit

      next if reasons.empty?

      puts "  #{org.name} (##{org.id}) — #{reasons.join(', ')} → comp Pro"
      org.update!(comped_indefinitely: true, comped_until: nil) if execute
      comped += 1
    end

    puts "\n#{execute ? 'Comped' : 'Would comp'} #{comped} organization(s)."
  end
end
