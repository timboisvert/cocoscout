# frozen_string_literal: true

require "rails_helper"

# The recurring-schedule editing was consolidated: the inline destructive
# rebuild and scope radios were removed from the Schedule tab, and series-wide
# changes (extend / reschedule / change pattern) now live in one guided modal.
RSpec.describe "Show schedule flow", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:location) { create(:location, organization: org) }

  let(:group_id) { SecureRandom.uuid }
  let!(:series) do
    (0..3).map do |i|
      production.shows.create!(event_type: "show", date_and_time: (i + 1).weeks.from_now.change(hour: 19),
                               location: location, recurrence_group_id: group_id, recurrence_pattern: "weekly")
    end
  end
  let(:first_show) { series.first }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders the guided series modal with all three operations" do
    get recurring_series_manage_production_shows_path(production, recurrence_group_id: group_id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Extend this series")
    expect(response.body).to include("Change schedule for future events")
    expect(response.body).to include("Change how often it repeats")
  end

  it "shows the guided-flow entry (not the old inline rebuild) on the edit Schedule tab" do
    get edit_manage_production_show_path(production, first_show)

    expect(response.body).to include("Change series schedule")
    # The old destructive inline control is gone.
    expect(response.body).not_to include("Change Schedule (Optional)")
  end

  it "rebuilds the whole series when the pattern changes (scope: all + pattern)" do
    patch manage_production_show_path(production, first_show), params: {
      show: {
        recurrence_edit_scope: "all",
        recurrence_pattern: "biweekly",
        recurrence_start_datetime: 1.week.from_now.change(hour: 20).strftime("%Y-%m-%dT%H:%M"),
        recurrence_end_type: "3_months"
      }
    }

    expect(response).to have_http_status(:redirect)
    # The old events are gone and a fresh biweekly set replaces them.
    rebuilt = production.shows.where(recurrence_group_id: group_id).order(:date_and_time).to_a
    expect(rebuilt.map(&:id) & series.map(&:id)).to be_empty
    gaps = rebuilt.each_cons(2).map { |a, b| (b.date_and_time.to_date - a.date_and_time.to_date).to_i }
    expect(gaps).to all(eq(14))
  end

  it "bulk-applies non-schedule fields to the whole series, keeping this occurrence's date" do
    new_time = first_show.date_and_time + 1.hour
    patch manage_production_show_path(production, first_show), params: {
      show: {
        recurrence_edit_scope: "all",
        event_type: "rehearsal",
        date_and_time: new_time
      }
    }

    expect(response).to have_http_status(:see_other)
    # Every event in the series became a rehearsal…
    expect(production.shows.where(recurrence_group_id: group_id).pluck(:event_type).uniq).to eq([ "rehearsal" ])
    # …but only THIS occurrence's date moved.
    expect(first_show.reload.date_and_time).to be_within(1.second).of(new_time)
    expect(series.second.reload.date_and_time).not_to be_within(1.hour).of(new_time)
  end
end
