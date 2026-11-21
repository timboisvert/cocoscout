# frozen_string_literal: true

require "rails_helper"

# Requesting more comps for one date (CompRequest; Tim, 2026-11-20): a
# production team manager or someone on a contract requests more from their
# Comps box, the organization's owners and managers get a notification, and
# one of them approves it, approves a different number, or declines it on
# the date's page, with a comment that goes back in a notification. Never
# an email.
RSpec.describe "Comp requests", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:owner_person) { create(:person, user: owner, name: "Tim Boisvert").tap { |p| owner.update!(default_person: p) } }
  let(:other_manager) { create(:user, email_address: "andie@sg.example", password: password) }
  let!(:other_role) { create(:organization_role, :manager, user: other_manager, organization: org) }
  let(:profile) { TicketingProfile.for(org) }

  # A production on a contract, with the contractor signed in on My.
  let!(:booked) { create(:production, organization: org, name: "Carded", production_type: "third_party") }
  let(:cora) { create(:user, email_address: "cora@example.com", password: password) }
  let!(:cora_person) { create(:person, user: cora, name: "Cora Contractor", email: "cora@example.com").tap { |p| cora.update!(default_person: p) } }
  let!(:contractor) { create(:contractor, organization: org, name: "Cora Contractor", email: "cora@example.com", person: cora_person) }
  let(:night) { 5.days.from_now.change(hour: 20, min: 0) }
  let!(:contract) { create(:contract, :active, organization: org, production: booked, contractor: contractor, contractor_name: "Cora Contractor", production_name: "Carded", shares_ticket_sales: true) }
  let!(:rental) { create(:space_rental, contract: contract, starts_at: night, ends_at: night + 3.hours) }
  let!(:booked_show) { create(:show, production: booked, space_rental: rental, date_and_time: night, duration_minutes: 120, event_type: "show") }
  let!(:booked_listing) { create(:ticket_listing, organization: org, show: booked_show).tap { |l| l.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 40) } }

  before { profile.update!(enabled: true, contract_comps_per_show: 3, contract_comp_requests: true) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def text = Nokogiri::HTML(response.body).at_css("body").text.gsub(/\s+/, " ")

  it "saves who may request more comps at the box office, in three boxes" do
    sign_in(owner)
    post set_organization_path(id: org.id)
    get manage_ticketing_settings_section_path(section: "comps")
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css("[data-settings-card]").map { |card| card["data-settings-card"] }).to eq(%w[comps team-comps contract-comps])
    expect(text).to include("Your own productions", "Productions on a contract", "Allow production team managers to issue comps",
                            "Allow production team managers to request more comps when they run out", "Allow contractors to issue comps",
                            "Allow contractors to request more comps when they run out")
    expect(response.body).not_to match(/\bask(ed|s)?\b/i)

    patch manage_ticketing_settings_comps_path, params: { ticketing_profile: { comps_enabled: "1", comps_limit: "unlimited", team_comps: "1", team_comps_limit: "all",
                                                                                contract_comps: "1", contract_comps_per_show: "3", team_comp_requests: "1", contract_comp_requests: "0" } }
    expect(profile.reload.team_comp_requests).to be(true)
    expect(profile.contract_comp_requests).to be(false)
  end

  it "lets the contractor request more, notifies the managers, and gives them back the approved number with the comment" do
    sign_in(cora)
    get my_show_tickets_path(booked_show)
    expect(response).to have_http_status(:ok)
    box = Nokogiri::HTML(response.body).at_css("[data-comps-box]")
    expect(box.text.squish).to include("Comps", "Request more comps", "Issue comps")
    expect(box.text.squish).to match(/For this date\s*3.*Issued\s*0.*Left to issue\s*3/)

    post my_show_ticket_comp_request_path(booked_show), params: { quantity: "4", note: "Our director's family is coming." }
    expect(flash[:notice]).to eq("Your request for 4 more comps has been sent. Stars & Garters has been notified.")
    request_row = CompRequest.sole
    expect(request_row).to have_attributes(side: "contract", quantity: 4, status: "waiting", requested_by: cora)
    notes = Notification.where(subject: request_row, kind: "comp_request_requested")
    expect(notes.map(&:user)).to contain_exactly(owner, other_manager)
    expect(notes.first.title).to eq("Cora Contractor requested 4 more comps: Carded, #{night.in_time_zone(org.time_zone.presence || Time.zone.name).strftime('%A, %B %-d at %-l:%M %p')}")
    expect(notes.first.path).to eq(manage_ticket_listing_path(booked_listing))
    expect(ActionMailer::Base.deliveries).to be_empty

    get my_show_tickets_path(booked_show)
    expect(text).to include("Requested", "You requested 4 more comps", "Withdraw the request")
    expect(Nokogiri::HTML(response.body).at_css("[data-comps-box]").text).not_to include("Request more comps")

    # A second request waits for the first.
    post my_show_ticket_comp_request_path(booked_show), params: { quantity: "1" }
    expect(flash[:alert]).to eq("There's already a request waiting for this date.")

    sign_in(owner)
    post set_organization_path(id: org.id)
    get manage_ticket_listing_path(booked_listing)
    card = Nokogiri::HTML(response.body).at_css("[data-comp-request='#{request_row.id}']")
    expect(card.text.squish).to include("Comp request", "Cora Contractor requested 4 more comps for this date",
                                        "Available seats", "Cora's note: Our director's family is coming.", "Approve 4 more", "Approve a different number", "Decline")
    expect(card.text.squish).to match(/Now\s*3.*Requested\s*4.*If approved\s*7/)

    post manage_approve_comp_request_path(request_row), params: { quantity: "2", comment: "Two is what we can spare." }
    expect(flash[:notice]).to eq("Approved 2 more comps. Cora Contractor has been notified.")
    expect(request_row.reload).to have_attributes(status: "approved", approved_quantity: 2, decided_by: owner, comment: "Two is what we can spare.")
    # The other manager's unopened notice is gone: there is nothing left to decide.
    expect(Notification.where(subject: request_row, kind: "comp_request_requested")).to be_empty
    answer = Notification.find_by!(user: cora, kind: "comp_request_approved")
    expect(answer.title).to start_with("Stars & Garters approved 2 of the 4 more comps you requested: Carded,")
    expect(answer.title).to end_with(%(Their comment: "Two is what we can spare."))
    expect(answer.path).to eq(my_show_tickets_path(booked_show))

    # Deciding it twice is refused.
    post manage_decline_comp_request_path(request_row)
    expect(flash[:alert]).to eq("This request was already approved.")

    allowance = TicketSalesAccess.comp_allowance(cora, booked_listing)
    expect(allowance).to include(team_limit: 5, left: 5, extra: 2)

    sign_in(cora)
    get my_show_tickets_path(booked_show)
    expect(text).to match(/For this date\s*5/)
    expect(text).to include("Includes 2 approved on request", "Approved", "approved 2 of the 4 more comps requested", "Their comment: Two is what we can spare.")
  end

  it "declines with a comment that reaches the contractor as a notification, and keeps their number" do
    request_row = CompRequest.request!(booked_listing, side: :contract, by: cora, quantity: 4)
    sign_in(owner)
    post set_organization_path(id: org.id)
    post manage_decline_comp_request_path(request_row), params: { comment: "We're nearly sold out." }
    expect(flash[:notice]).to eq("Declined. Cora Contractor has been notified.")
    answer = Notification.find_by!(user: cora, kind: "comp_request_declined")
    expect(answer.title).to start_with("Stars & Garters declined your request for 4 more comps: Carded,")
    expect(answer.title).to end_with(%(Their comment: "We're nearly sold out."))
    expect(TicketSalesAccess.comp_allowance(cora, booked_listing)).to include(team_limit: 3, extra: 0)
    expect(ActionMailer::Base.deliveries).to be_empty

    sign_in(cora)
    get my_show_tickets_path(booked_show)
    expect(text).to include("Declined", "declined the request for 4 more comps", "Your comps for this date are unchanged.", "Their comment: We're nearly sold out.")
    expect(text).to include("Request more comps")
  end

  it "lets the contractor withdraw a request, and removes the managers' unopened notifications" do
    sign_in(cora)
    post my_show_ticket_comp_request_path(booked_show), params: { quantity: "2" }
    request_row = CompRequest.sole
    delete my_show_ticket_comp_request_path(booked_show)
    expect(flash[:notice]).to eq("Your request was withdrawn.")
    expect(request_row.reload.status).to eq("withdrawn")
    expect(Notification.where(subject: request_row)).to be_empty
  end

  it "offers no request when the side may not request, and closes waiting ones when it is switched off" do
    request_row = CompRequest.request!(booked_listing, side: :contract, by: cora, quantity: 2)
    profile.update!(contract_comp_requests: false)
    CompRequest.close_turned_off!(org)
    expect(request_row.reload).to have_attributes(status: "closed", closed_reason: "turned_off")
    expect(Notification.find_by!(user: cora, kind: "comp_request_closed").title).to end_with("was closed: Stars & Garters no longer takes comp requests for that date")

    sign_in(cora)
    get my_show_tickets_path(booked_show)
    expect(Nokogiri::HTML(response.body).at_css("[data-comps-box]").text).not_to include("Request more comps")
    post my_show_ticket_comp_request_path(booked_show), params: { quantity: "2" }
    expect(flash[:alert]).to eq("Contractors can't request more comps for this date.")
  end

  it "closes a request nobody decided once the date starts" do
    request_row = CompRequest.request!(booked_listing, side: :contract, by: cora, quantity: 2)
    booked_show.update_columns(date_and_time: 1.minute.ago)
    CompRequestExpiryJob.perform_now
    expect(request_row.reload).to have_attributes(status: "closed", closed_reason: "showtime")
    expect(Notification.find_by!(user: cora, kind: "comp_request_closed").title).to end_with("was closed: the date started before anyone decided it")
  end

  it "raises the date's total by the approved number, whatever the cap said" do
    profile.update!(comps_limit: "fixed", comps_per_show: 3)
    expect(booked_listing.comps_left).to eq(3)
    CompRequest.request!(booked_listing, side: :contract, by: cora, quantity: 4).approve!(by: owner)
    expect(booked_listing.reload.comps_left).to eq(7)
    expect(TicketSalesAccess.comp_allowance(cora, booked_listing)).to include(team_limit: 7, left: 7)
  end

  it "never lets another organization decide a request" do
    request_row = CompRequest.request!(booked_listing, side: :contract, by: cora, quantity: 2)
    stranger = create(:user, password: password)
    theirs = create(:organization, :pro, owner: stranger)
    create(:organization_role, :manager, user: stranger, organization: theirs)
    sign_in(stranger)
    post set_organization_path(id: theirs.id)
    post manage_approve_comp_request_path(request_row)
    expect(response).to have_http_status(:not_found)
    expect(request_row.reload.status).to eq("waiting")
  end

  describe "for a production team manager" do
    let!(:production) { create(:production, organization: org, name: "Stargazers") }
    let!(:show) { create(:show, production: production, date_and_time: 6.days.from_now.change(hour: 19, min: 30)) }
    let!(:listing) { create(:ticket_listing, organization: org, show: show).tap { |l| l.ticket_tiers.create!(name: "General", price_cents: 3_000, quantity: 80) } }
    let(:clay) { create(:user, email_address: "clay@sg.example", password: password) }
    let!(:clay_person) { create(:person, user: clay, name: "Clay Smith").tap { |p| clay.update!(default_person: p) } }

    before do
      profile.update!(team_comps_limit: "fixed", team_comps_per_show: 2, team_comp_requests: true)
      create(:organization_role, user: clay, organization: org, company_role: "member")
      ProductionPermission.create!(user: clay, production: production, role: "manager")
    end

    it "shows the Comps box on their sales page and sends the request as the production team's" do
      sign_in(clay)
      post set_organization_path(id: org.id)
      get manage_production_sale_path(production, listing)
      expect(response).to have_http_status(:ok)
      box = Nokogiri::HTML(response.body).at_css("[data-comps-box]")
      expect(box.text.squish).to match(/For this date\s*2/)
      expect(box.text.squish).to include("For your production team", "By your production team", "Request more comps")

      post manage_production_sale_comp_request_path(production, listing), params: { quantity: "3" }
      expect(CompRequest.sole).to have_attributes(side: "team", quantity: 3)
      expect(Notification.where(kind: "comp_request_requested").map(&:user)).to contain_exactly(owner, other_manager)

      CompRequest.sole.approve!(by: owner)
      expect(Notification.find_by!(user: clay, kind: "comp_request_approved").path).to eq(manage_production_sale_path(production, listing))
      expect(TicketSalesAccess.comp_allowance(clay, listing)).to include(team_limit: 5, extra: 3)
    end
  end
end
