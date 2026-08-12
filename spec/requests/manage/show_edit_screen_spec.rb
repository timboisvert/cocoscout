# frozen_string_literal: true

require "rails_helper"

# The edit-show screen was reorganized into wizard-aligned tabs. These specs
# pin that the screen renders (both single and recurring shows) and that Save
# still writes each tab's fields.
RSpec.describe "Edit-show screen", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:location) { create(:location, organization: org) }
  let!(:show) do
    production.shows.create!(event_type: "show", date_and_time: 2.weeks.from_now, location: location)
  end

  before { post handle_signin_path, params: { email_address: owner.email_address, password: password } }

  it "renders every regrouped tab" do
    get edit_manage_production_show_path(production, show)

    expect(response).to have_http_status(:ok)
    %w[Details Schedule Location].each { |t| expect(response.body).to include(t) }
    expect(response.body).to include("Casting &amp; Visibility")
    expect(response.body).to include("Poster, Links &amp; Notes")
    expect(response.body).to include("Danger Zone")
    # Event type is now a radio-card grid, not a <select>.
    expect(response.body).to include('name="show[event_type]"')
    expect(response.body).to include("Save Changes")
  end

  it "renders for a recurring show without error" do
    group_id = SecureRandom.uuid
    3.times do |i|
      production.shows.create!(event_type: "show", date_and_time: (i + 2).weeks.from_now,
                               location: location, recurrence_group_id: group_id, recurrence_pattern: "weekly")
    end
    recurring = production.shows.where(recurrence_group_id: group_id).first

    get edit_manage_production_show_path(production, recurring)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("recurring")
  end

  it "saves fields from the reorganized tabs" do
    patch manage_production_show_path(production, show), params: {
      show: {
        event_type: "rehearsal",
        secondary_name: "Understudy Night",
        notes: "Bring scripts",
        casting_enabled: "1",
        date_and_time: show.date_and_time
      }
    }

    show.reload
    expect(show.event_type).to eq("rehearsal")
    expect(show.secondary_name).to eq("Understudy Night")
    expect(show.notes).to eq("Bring scripts")
    expect(show.casting_enabled).to be(true)
  end
end
