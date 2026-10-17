# frozen_string_literal: true

require "rails_helper"

# The Door in the My dashboard (Tim, 2026-10-17): never a menu item, always
# the pink "Work the door" bar under the menu, on the desktop sidebar and
# the phone menu alike, only while a show the person can work is on
# (NavigationHelper#door_bar_item, the same rule as the app's menu).
RSpec.describe "The Work the door bar", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true) } }
  let(:production) { create(:production, organization: org, name: "Stargazers") }
  let(:door_person) { create(:user, password: password) }
  let!(:person) { create(:person, user: door_person, name: "Dana Door").tap { |p| door_person.update!(default_person: p) } }

  before do
    org.ticketing_access_grants.create!(user: door_person, access_level: "check_in")
    post handle_signin_path, params: { email_address: door_person.email_address, password: password }
  end

  it "draws the bar under the menu while a show is on, and never a Door menu item" do
    tonight = create(:ticket_listing, organization: org, status: "on_sale",
                     show: create(:show, production: production, date_and_time: Time.current.end_of_day - 1.hour))
    get my_shows_path
    expect(response).to have_http_status(:ok)
    expect(response.body.scan("data-door-bar").size).to eq(2) # the sidebar and the phone menu
    expect(response.body).to include("Work the door", "Starts #{tonight.show.date_and_time.strftime('%-l:%M %p')}", door_index_path)
    expect(response.body).not_to include(">Door<", "Ticket Sales")
  end

  it "draws nothing when no show is on, unless the organization keeps the Door all the time" do
    create(:ticket_listing, organization: org, status: "on_sale", show: create(:show, production: production, date_and_time: 5.days.from_now))
    get my_shows_path
    expect(response.body).not_to include("data-door-bar", ">Door<")

    profile.update!(door_in_app: "always")
    get my_shows_path
    expect(response.body).to include("data-door-bar", "Work the door", "Next: ")
  end
end
