# frozen_string_literal: true

require "rails_helper"

# Role Call gates on Shift#fully_staffed?, so while a declined assignment still
# counted as staffing its shift, a show whose only tech had dropped out went on
# reading as covered. The amber "needs …" chip is the thing that has to come back.
RSpec.describe "Manage::Staffing Role Call after a decline", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, alert_uncovered_show_roles: true) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:production) { create(:production, organization: org) }

  let!(:tech) do
    create(:house_role, organization: org, name: "Tech",
                        role_type: :show_specific, include_in_role_call: true)
  end

  # A fixed Wednesday, so the week the page renders never depends on today.
  let(:show_at) { Time.zone.local(2026, 9, 16, 20, 0) }
  let!(:show) do
    create(:show, production: production, location: location, date_and_time: show_at, duration_minutes: 120)
  end

  let!(:shift) do
    create(:shift, organization: org, house_role: tech, source: show, required_count: 1,
                   starts_at: show_at - 1.hour, ends_at: show_at + 3.hours)
  end
  let(:staffer) { create(:person, name: "Quinn") }
  let!(:assignment) { shift.shift_assignments.create!(person: staffer, position: 1) }

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  def scheduling!
    get manage_staffing_scheduling_path(week_start: show_at.to_date.beginning_of_week.to_s)
  end

  it "reads the show as covered while the tech is still on" do
    scheduling!

    expect(response).to have_http_status(:ok)
    # The show has to actually be on the rendered week, or the absence of the
    # chip below would prove nothing.
    expect(response.body).to include(production.name)
    expect(response.body).not_to include("needs Tech")
  end

  it "flags the show as needing the role once the tech can't make it" do
    assignment.decline!(reason: "Sick")

    scheduling!

    expect(response.body).to include("needs Tech")
  end

  it "covers it again once they're back on" do
    assignment.decline!
    assignment.undo_decline!

    scheduling!

    expect(response.body).not_to include("needs Tech")
  end
end
