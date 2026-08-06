# frozen_string_literal: true

require "rails_helper"

# Recurring series generation. Two bugs lived here:
#
#   1. Derived dates dropped the time — only the seed date kept it, so a
#      "1st Thursday at 8pm" series came out as 8pm, then midnight, midnight.
#      (Real damage: production 130's series from 2026-05-05.)
#   2. The by-weekday branch called `>>` on a TimeWithZone, which is a Date
#      method — every "Monthly (e.g. 2nd Friday)" series raised NoMethodError.
#      Reachable on every such series, since the Which Week select defaults to
#      "First" and the Day of Week select always submits a value.
RSpec.describe "Show wizard — recurring series", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:location) { create(:location, organization: org) }

  let(:wizard_cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(wizard_cache)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  # First Thursday of June 2026, 8pm.
  def create_series(extra = {})
    post manage_shows_wizard_save_event_type_path(production), params: { event_type: "show" }
    post manage_shows_wizard_save_schedule_path(production), params: {
      event_frequency: "recurring",
      duration_minutes: "120",
      recurrence_start_datetime: "2026-06-04T20:00",
      recurrence_pattern: "monthly_week",
      recurrence_end_type: "3_months"
    }.merge(extra)
    post manage_shows_wizard_save_location_path(production), params: { is_online: "false", location_id: location.id }
    post manage_shows_wizard_save_details_path(production), params: { secondary_name: "" }
    post manage_shows_wizard_create_path(production)
    production.shows.order(:date_and_time).to_a
  end

  it "keeps the chosen time on every date, not just the first" do
    shows = create_series(recurrence_week_ordinal: "1", recurrence_weekday: "4")

    expect(shows).not_to be_empty
    expect(shows.map { |s| s.date_and_time.strftime("%H:%M") }).to all(eq("20:00"))
  end

  it "lands on the 1st Thursday of each month" do
    shows = create_series(recurrence_week_ordinal: "1", recurrence_weekday: "4")

    expect(shows.map { |s| s.date_and_time.to_date.to_s }).to start_with(
      [ "2026-06-04", "2026-07-02", "2026-08-06" ]
    )
    expect(shows.map { |s| s.date_and_time.wday }).to all(eq(4))
  end

  it "doesn't raise when the week/day selects are submitted (they always are)" do
    expect { create_series(recurrence_week_ordinal: "2", recurrence_weekday: "5") }.not_to raise_error
    expect(production.shows.count).to be_positive
  end

  it "still keeps the time when no ordinal was chosen" do
    shows = create_series(recurrence_week_ordinal: "", recurrence_weekday: "")

    expect(shows.map { |s| s.date_and_time.strftime("%H:%M") }).to all(eq("20:00"))
  end

  it "groups the series so they travel together" do
    shows = create_series(recurrence_week_ordinal: "1", recurrence_weekday: "4")

    expect(shows.map(&:recurrence_group_id).uniq.compact.size).to eq(1)
    expect(shows.map(&:recurrence_pattern).uniq).to eq([ "monthly_week" ])
  end
end
