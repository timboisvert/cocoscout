# frozen_string_literal: true

require "rails_helper"

# A contract date's move (Cancel or move this date, Tim 2026-11-27): the
# night is the space rental, the show runs at its own times inside it, and a
# contractor's request fills the page in. Confirming it moves the rental and
# the show together (or either alone) and answers the request.
RSpec.describe "Moving a contract date", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let!(:owner) { create(:user, password: password) }
  let!(:owner_person) { create(:person, user: owner) }
  let!(:org) { create(:organization, :pro, owner: owner) }
  let!(:asker) { create(:user) }
  let!(:asker_person) { create(:person, user: asker, name: "Dana Ortiz") }
  let!(:contractor) { create(:contractor, organization: org, person: asker_person) }
  let!(:production) { create(:production, organization: org, production_type: "third_party", name: "Northside Sketch Co.") }
  let!(:contract) do
    create(:contract, :active, organization: org, production: production, contractor: contractor,
                               contractor_name: "Northside Sketch Co.", contractor_email: contractor.email)
  end
  let!(:location) { create(:location, organization: org) }
  let(:night) { 1.month.from_now.in_time_zone(org.time_zone).change(hour: 18, min: 0) }
  let!(:rental) do
    contract.space_rentals.create!(location: location, starts_at: night, ends_at: night + 5.hours, confirmed: true,
                                   event_starts_at: night + 2.hours, event_ends_at: night + 4.hours)
  end
  let!(:show) { production.shows.create!(date_and_time: night + 2.hours, duration_minutes: 120, location: location, space_rental: rental) }
  let(:week_later) { night + 7.days }
  let!(:date_request) do
    ContractDateRequests.ask!(contract: contract, user: asker, show: show, kind: "move", proposed_at: week_later + 2.hours, note: "Our lead is out of town.")
  end

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def page = Nokogiri::HTML(response.body)

  it "opens on the request, shows the rental with the show inside it, and moves the whole night" do
    get manage_contract_path(contract)
    expect(response.body).to include(manage_move_contract_date_path(contract, show, request_id: date_request.id).gsub("&", "&amp;"))

    get manage_move_contract_date_path(contract, show, request_id: date_request.id)
    change = DateChange.last
    expect(change).to have_attributes(kind: "move", contract_id: contract.id, contract_date_request_id: date_request.id)
    expect(response).to redirect_to(manage_date_change_touches_path(change))
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(page.text).to include("Dana Ortiz requested this move", "Space rental · 6:00 PM to 11:00 PM", "Show · 8:00 PM to 10:00 PM",
                                 "The whole night", "Only the show's times", "Only the rental")
    expect(page.at_css("input[name='move[date]']")["value"]).to eq(week_later.to_date.iso8601)

    patch manage_date_change_touches_path(change), params: { commit: "review", move: { what: "night", date: week_later.to_date.iso8601, rental_starts: "18:00", rental_ends: "23:00", own_times: "1", show_starts: "20:00", show_ends: "22:00", location_space_id: "" } }
    expect(response).to redirect_to(manage_date_change_review_path(change))
    follow_redirect!
    expect(response).to have_http_status(:ok)

    perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }
    expect(rental.reload.starts_at).to eq(week_later)
    expect(rental.event_starts_at).to eq(week_later + 2.hours)
    expect(show.reload.date_and_time).to eq(week_later + 2.hours)
    expect(date_request.reload.status).to eq("done")
    expect(change.reload.steps.map { |s| [ s["key"], s["status"], s["detail"] ] }).to all(satisfy { |e| e[1] == "done" })
  end

  it "moves only the show's times inside the same rental" do
    get manage_move_contract_date_path(contract, show)
    change = DateChange.last
    patch manage_date_change_touches_path(change), params: { commit: "review", move: { what: "show", show_starts: "19:30", show_ends: "21:30" } }
    expect(response).to redirect_to(manage_date_change_review_path(change))
    perform_enqueued_jobs(only: DateChangeApplyJob) { post manage_apply_date_change_path(change) }
    expect(rental.reload.starts_at).to eq(night)
    expect(rental.ends_at).to eq(night + 5.hours)
    expect(show.reload.date_and_time).to eq(night + 90.minutes)
  end

  it "won't let the show run outside the rental" do
    get manage_move_contract_date_path(contract, show)
    change = DateChange.last
    patch manage_date_change_touches_path(change), params: { commit: "review", move: { what: "show", show_starts: "17:00", show_ends: "19:00" } }
    expect(response).to redirect_to(manage_date_change_touches_path(change))
    expect(flash[:alert]).to eq("The show has to start and end inside the rental.")
  end
end
