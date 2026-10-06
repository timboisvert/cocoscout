# frozen_string_literal: true

# The morning digest lists only what sold (or was refunded) yesterday, with
# where each of those shows stands now; the "Coming up" table of every show
# is gone (Tim, 2026-10-06). Re-seeds the template with the new body.
class DailySummaryYesterdayOnly < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(keys: %w[ticketing_daily_summary], overwrite: true)
  end

  def down; end
end
