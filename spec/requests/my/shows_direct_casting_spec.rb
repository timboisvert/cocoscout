# frozen_string_literal: true

require "rails_helper"

# A performer cast directly into a single show (without being in the production's
# talent pool) should still see it under "My Shows & Events" — the same way the
# homepage calendar shows it. Regression: index only sourced shows from talent
# pools and sign-ups, so a one-off casting was missing.
RSpec.describe "My::Shows direct casting", type: :request do
  let(:password) { "Password123!" }
  let!(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user) }
  let!(:org) { create(:organization) }
  let!(:production) { create(:production, organization: org) }
  # Casting finalized (as the manager did before notifying), so assignments are
  # visible to performers.
  let!(:show) do
    create(:show, production: production, date_and_time: 3.weeks.from_now, event_type: "show",
      casting_finalized_at: Time.current)
  end

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "lists a show the person is directly cast in, without talent-pool membership" do
    role = create(:role, production: production, name: "Aerialist")
    create(:show_person_role_assignment, show: show, assignable: person, role: role)

    get my_shows_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(production.name)
  end

  it "does not list a show the person is neither cast in nor pooled for" do
    other_person = create(:person)
    role = create(:role, production: production, name: "Aerialist")
    create(:show_person_role_assignment, show: show, assignable: other_person, role: role)

    get my_shows_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(production.name)
  end
end
