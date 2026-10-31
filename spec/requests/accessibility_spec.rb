# frozen_string_literal: true

require "rails_helper"

# Accessibility (accessibility plan §1, §2, §4; V1.4): a location's and
# room's answers summed up in plain words; a date's access services and
# content notes; the show page's quiet Accessibility line and the room's
# access guide; a buyer's access needs seen by the box office and the door
# only, and purged a month after the show.
RSpec.describe "Accessibility", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let!(:location) { create(:location, organization: org, name: "The Lodge") }
  let(:room) { location.default_room }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:setup) { ProductionTicketing.create!(production: production, organization: org, enabled: true) }
  let!(:general) { setup.ticket_tiers.create!(name: "General", price_cents: 2_500, quantity: 50) }
  let!(:show) { create(:show, production: production, location: location, location_space: room, date_and_time: 20.days.from_now.change(hour: 19)) }
  let!(:other_show) { create(:show, production: production, location: location, location_space: room, date_and_time: 21.days.from_now.change(hour: 19)) }
  let(:listing) { ProductionTicketingDates.sync!(setup); TicketListing.find_by!(show: show) }

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "answers feature by feature on the location, lets a room differ, labels a date, and shows it all to buyers in one quiet line" do
    get manage_location_path(location)
    expect(response.body).to include("Accessibility", "Accessibility details not listed yet", manage_location_access_path(location))

    get manage_location_access_path(location)
    expect(response.body).to include("Step-free route from the street", "Who to ask", "Backstage")
    patch manage_location_access_path(location), params: {
      answers: { step_free_entry: "yes", accessible_restroom: "yes", assistive_listening: "ask", step_free_stage: "yes", lift: "no" },
      notes: { assistive_listening: "Headsets at the bar" }, location: { access_email: "access@lodge.example" }
    }
    expect(response).to redirect_to(manage_location_path(location))
    expect(location.access_answers.count).to eq(5)
    expect(location.access_profile.guest_summary).to eq("Step-free entrance, accessible restroom")
    expect(location.access_profile.backstage_summary).to eq("Step-free entrance, step-free to the stage")

    # The room inherits, then says what's different here.
    get manage_location_space_access_path(location, room)
    expect(response.body).to include("Only in this room", "Location says yes", "Same as the location")
    patch manage_location_space_access_path(location, room), params: {
      answers: { accessible_restroom: "no" }, location_space: { wheelchair_spaces: 2, wheelchair_spaces_note: "Front left, level with the stage", stage_access: "ramp" }
    }
    room.reload
    expect(room.access_answers.pluck(:feature_key)).to eq([ "accessible_restroom" ])
    room_profile = room.access_profile
    expect(room_profile.yes?("step_free_entry")).to be(true)
    expect(room_profile.inherited?("step_free_entry")).to be(true)
    expect(room_profile.answer("accessible_restroom")).to eq("no")
    expect(room_profile.guest_summary).to eq("Step-free entrance, 2 wheelchair spaces")
    get manage_location_space_path(location, room)
    expect(response.body).to include("Step-free entrance, 2 wheelchair spaces", "Front left, level with the stage")

    # A date's services and notes; the production's notes reach every date.
    patch manage_update_show_path(production, show), params: { show: {
      access_services_attributes: { "0" => { service: "interpreted", detail: "ASL", _destroy: "0" }, "1" => { service: "captioned", _destroy: "1" } },
      content_note_keys: [ "", "strobe" ], content_note_text: "A little stage smoke"
    } }
    show.reload
    expect(show.access_labels).to eq([ "Interpreted" ])
    expect(show.content_note_keys).to eq([ "strobe" ])
    patch manage_production_path(production), params: { production: { content_note_keys: [ "", "haze", "bogus" ] } }
    expect(production.reload.content_note_keys).to eq([ "haze" ])
    expect(show.effective_content_note_words).to eq([ "Haze or fog", "Strobe or flashing lights", "A little stage smoke" ])
    get manage_edit_show_path(production, show)
    expect(response.body).to include("Accessibility and content notes", "Interpreted", "From the production, on every date: Haze or fog")

    # Buyers: one line, a pop-up, labels on the date, the guide.
    listing
    get tickets_event_path(org: "starsandgarters", event: production.public_key)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Interpreted")
    get tickets_event_path(org: "starsandgarters", event: listing.slug)
    expect(response.body).to include("Accessibility", "Step-free entrance", "2 wheelchair spaces", "Before you come", "Haze or fog", "Interpreted (ASL)",
                                     tickets_access_guide_path(org: "starsandgarters", room: room.id), "access@lodge.example")
    expect(response.body).not_to include("compliant")

    get tickets_access_guide_path(org: "starsandgarters", room: room.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Getting to Main room", "2 wheelchair spaces", "Front left, level with the stage", "Headsets at the bar", "Ask us", "access@lodge.example")
    expect(response.body).not_to include("Accessible restroom for guests")
  end

  it "takes a buyer's access needs at checkout, shows them to the door and box office only, puts the guide on the email, and purges them after the show" do
    location.access_answers.create!(feature_key: "step_free_entry", answer: "yes")
    date_general = listing.ticket_tiers.find_by!(source_tier_id: general.id)
    order = TicketCheckout.start!(listing: listing, quantities: { date_general.id.to_s => "2" })
    get tickets_checkout_path(token: order.token)
    expect(response.body).to include("Any access needs for your visit?", "A step-free route in", "Someone to meet us at the door")
    expect(response.body).not_to include("see the interpreter")

    order.update_columns(created_at: 1.minute.ago)
    intent = Stripe::PaymentIntent.construct_from(id: "pi_access", client_secret: "pi_access_secret", amount: order.card_cents, status: "requires_payment_method")
    allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)
    post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Bella Swan", buyer_email: "bella@example.com",
                                                                 access_request_keys: [ "", "step_free", "meet_at_door" ], access_note: " Aisle, please " }, as: :json
    expect(response).to have_http_status(:ok)
    request = order.reload.access_request
    expect(request.request_keys).to eq(%w[step_free meet_at_door])
    expect(request.words).to eq("step-free route, meet at the door, Aisle, please")
    get tickets_checkout_path(token: order.token)
    expect(response.body).to include("Access needs: step-free route, meet at the door, Aisle, please · Change")

    perform_enqueued_jobs { TicketOrderSettlement.settle!(order, payment_intent_id: "pi_access") }
    confirmation = ActionMailer::Base.deliveries.find { |m| m.to == [ "bella@example.com" ] }
    expect(confirmation.html_part.body.to_s).to include("Your visit:", "Step-free entrance", "/tickets/starsandgarters/access/#{room.id}")
    expect(TicketPdf.new(order).render.bytesize).to be > 1000

    # The box office and the door see it; the public order page doesn't repeat it.
    get manage_ticket_orders_path(listing_id: listing.id)
    expect(response.body).to include(">Access<")
    travel_to(show.date_and_time - 2.hours) do
      get door_path(listing)
      expect(response.body).to include("Access needs tonight", "Bella Swan", "step-free route, meet at the door")
      post door_check_in_path(listing), params: { code: order.tickets.first.code }, as: :json
      expect(response.parsed_body["access"]).to eq("step-free route, meet at the door, Aisle, please")
    end
    get tickets_order_path(token: order.token)
    expect(response.body).not_to include("Aisle, please")

    # Gone a month after the show.
    travel_to(show.date_and_time + 29.days) { PurgeAccessRequestsJob.perform_now }
    expect(TicketOrderAccessRequest.exists?(request.id)).to be(true)
    travel_to(show.date_and_time + 31.days) { PurgeAccessRequestsJob.perform_now }
    expect(TicketOrderAccessRequest.exists?(request.id)).to be(false)
  end
end
