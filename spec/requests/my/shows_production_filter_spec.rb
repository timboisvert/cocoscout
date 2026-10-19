# frozen_string_literal: true

require "rails_helper"

# My Shows & Events carries the pink production filter from Manage → Shows &
# Events for anyone whose dates span more than one production, listing only
# the productions in their view.
RSpec.describe "My::Shows production filter", type: :request do
  let(:password) { "Password123!" }
  let!(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user) }
  let!(:org) { create(:organization) }
  let!(:alpha) { create(:production, organization: org, name: "Alpha Revue") }
  let!(:bravo) { create(:production, organization: create(:organization), name: "Bravo Cabaret") }
  let!(:outsider) { create(:production, organization: create(:organization), name: "Charlie Outsider") }

  def cast_in(production, at:)
    show = create(:show, production: production, date_and_time: at, event_type: "show", casting_finalized_at: Time.current)
    role = create(:role, production: production, name: "Aerialist")
    create(:show_person_role_assignment, show: show, assignable: person, role: role)
    show
  end

  before do
    cast_in(alpha, at: 2.weeks.from_now)
    cast_in(bravo, at: 3.weeks.from_now)
    create(:show, production: outsider, date_and_time: 2.weeks.from_now, event_type: "show")
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "offers only the person's productions" do
    get my_shows_path

    expect(response.body).to include("All Productions")
    expect(response.body).to include("Alpha Revue", "Bravo Cabaret")
    expect(response.body).not_to include("Charlie Outsider")
  end

  it "narrows the list to the chosen production" do
    get my_shows_path
    unfiltered = response.body.scan("Bravo Cabaret").size

    get my_shows_path(production: alpha.id)

    expect(response.body.scan("Bravo Cabaret").size).to be < unfiltered
    expect(response.body.scan("Alpha Revue").size).to be > response.body.scan("Bravo Cabaret").size
  end

  it "ignores a production outside their view" do
    get my_shows_path(production: outsider.id)

    expect(response.body).not_to include("Charlie Outsider")
    expect(response.body.scan("Bravo Cabaret").size).to be > 1
  end

  it "has no production filter with only one production" do
    ShowPersonRoleAssignment.joins(:show).where(shows: { production_id: bravo.id }).destroy_all

    get my_shows_path

    expect(response.body).not_to include("All Productions")
  end
end
