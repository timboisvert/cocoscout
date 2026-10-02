# frozen_string_literal: true

require "rails_helper"

# The door lives outside /manage because the people working it often aren't
# org members: managers, plus anyone granted door access. Each listing is
# judged against its own organization, so a grant at one theater opens
# nothing at another.
RSpec.describe "Door", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true) } }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 20) }
  let(:door_person) { create(:user, password: password) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def grant(user, level, organization: org)
    organization.ticketing_access_grants.create!(user: user, access_level: level)
  end

  def sold_order(count = 2)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com")
    TicketOrderSettlement.settle!(order)
    order.reload
  end

  it "needs a sign-in" do
    get door_path(listing)
    expect(response).to redirect_to(signin_path)
  end

  describe "who gets in" do
    it "opens for someone with a grant, and lists that theater's shows" do
      grant(door_person, "check_in")
      sign_in(door_person)
      get door_index_path
      expect(response.body).to include(door_path(listing))

      get door_path(listing)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Find someone")
      expect(response.body).not_to include("At the door")
    end

    it "shows door sales to box office and managers" do
      grant(door_person, "box_office")
      sign_in(door_person)
      get door_path(listing)
      expect(response.body).to include("Sell tickets", "Card or phone pay")
    end

    it "is not found for someone without access, a revoked grant, or a theater that isn't switched on" do
      sign_in(door_person)
      get door_path(listing)
      expect(response).to have_http_status(:not_found)

      grant(door_person, "check_in").revoke!
      get door_path(listing)
      expect(response).to have_http_status(:not_found)

      grant(door_person, "check_in")
      profile.update!(enabled: false)
      get door_path(listing)
      expect(response).to have_http_status(:not_found)
      get door_index_path
      expect(response.body).not_to include(door_path(listing))
    end

    it "opens nothing at another theater" do
      other_org = create(:organization, :pro)
      TicketingProfile.for(other_org).update!(enabled: true)
      other_listing = create(:ticket_listing, organization: other_org)
      grant(door_person, "box_office")
      sign_in(door_person)

      get door_path(other_listing)
      expect(response).to have_http_status(:not_found)
      post door_check_in_path(other_listing), params: { code: "x" }, as: :json
      expect(response).to have_http_status(:not_found)
      post door_sell_path(other_listing), params: { quantities: { "1" => "1" }, kind: "comp" }
      expect(response).to have_http_status(:not_found)
    end

    it "lets the theater's managers in without a grant" do
      sign_in(owner)
      get door_path(listing)
      expect(response).to have_http_status(:ok)
    end

    it "puts Door in the My sidebar for people with a grant" do
      grant(door_person, "check_in")
      sign_in(door_person)
      get my_dashboard_path
      expect(response.body).to include(door_index_path)
    end
  end

  describe "working the door" do
    before do
      grant(door_person, "check_in")
      sign_in(door_person)
    end

    it "checks a scanned ticket in and says so" do
      ticket = sold_order(1).tickets.sole
      post door_check_in_path(listing), params: { code: "https://cocoscout.com/t/v/#{ticket.code}" }, as: :json
      expect(response.parsed_body.slice("kind", "holder", "counts"))
        .to eq("kind" => "admitted", "holder" => "Dana Scully", "counts" => { "checked_in" => 1, "sold" => 1, "capacity" => 20 })

      post door_check_in_path(listing), params: { code: ticket.code }, as: :json
      expect(response.parsed_body["kind"]).to eq("already")
    end

    it "finds people by name, email or order code, and checks in a whole order" do
      order = sold_order(3)
      %w[scul DANA@example].each do |q|
        get door_search_path(listing), params: { q: q }
        expect(response.body).to include("Dana Scully")
      end
      get door_search_path(listing), params: { q: order.code.downcase }
      expect(response.body).to include("Check in all 3")
      get door_search_path(listing), params: { q: "nobody" }
      expect(response.body).to include("Nobody matching")

      post door_check_in_order_path(listing, order_id: order.id), as: :json
      expect(response.parsed_body["message"]).to eq("Admitted 3 — Dana Scully")
      get door_stats_path(listing)
      expect(response.parsed_body).to eq("checked_in" => 3, "sold" => 3, "capacity" => 20)
    end

    it "undoes a mistaken check-in" do
      ticket = sold_order(1).tickets.sole
      post door_check_in_path(listing), params: { code: ticket.code }, as: :json
      post door_undo_path(listing), params: { ticket_id: ticket.id }, as: :json
      expect(response.parsed_body["ok"]).to be(true)
      expect(ticket.reload.status).to eq("valid")
    end

    it "keeps check-in-only people away from door sales" do
      post door_sell_path(listing), params: { quantities: { general.id.to_s => "1" }, kind: "comp" }
      expect(response).to redirect_to(door_path(listing))
      expect(flash[:alert]).to include("box office access")
      expect(listing.ticket_orders).to be_empty
    end
  end

  it "sells for cash and comps at the door with box office access" do
    grant(door_person, "box_office")
    sign_in(door_person)

    post door_sell_path(listing), params: { quantities: { general.id.to_s => "2" }, kind: "cash", buyer_name: "Walk-up" }
    expect(response).to redirect_to(door_path(listing))
    expect(flash[:notice]).to eq("Sold 2 at the door — collect $40.00 cash.")

    post door_sell_path(listing), params: { quantities: { general.id.to_s => "1" }, kind: "comp" }
    expect(flash[:notice]).to eq("Comped 1 and checked them in.")
    expect(listing.ticket_orders.pluck(:channel)).to contain_exactly("door_cash", "comp")

    post door_sell_path(listing), params: { quantities: { general.id.to_s => "50" }, kind: "cash" }
    expect(flash[:alert]).to include("more than the seats left")
  end

  # Tim (2026-10-02): take a card at the door on a phone. The buyer scans a
  # code and pays on their own phone; the door screen flips to Paid.
  describe "card or phone pay at the door" do
    before do
      grant(door_person, "box_office")
      sign_in(door_person)
    end

    it "holds the seats, shows a code to scan, and checks them in when paid" do
      listing.update!(status: "closed") # online sales are over; the door still sells
      post door_sell_path(listing), params: { quantities: { general.id.to_s => "2" }, kind: "card", buyer_name: "Walk Up" }
      order = listing.ticket_orders.sole
      expect(order.attributes.slice("status", "channel", "money_path", "buyer_name", "issued_by_id", "total_cents"))
        .to eq("status" => "pending", "channel" => "door_card", "money_path" => "cocoscout", "buyer_name" => "Walk Up",
               "issued_by_id" => door_person.id, "total_cents" => 4_253)
      expect(response).to redirect_to(door_card_path(listing, token: order.token))

      follow_redirect!
      expect(response.body).to include("$42.53", "Scan with your phone", "<svg", "Paying at the door")
      get door_card_status_path(listing, token: order.token)
      expect(response.parsed_body["status"]).to eq("pending")

      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_door")
      expect(order.tickets.reload.pluck(:status, :checked_in_by_id)).to all(eq([ "checked_in", door_person.id ]))
      get door_card_status_path(listing, token: order.token)
      expect(response.parsed_body).to include("status" => "paid", "message" => "2 tickets paid by card, checked in.")
    end

    it "lets the buyer pay without giving their details, and cancels cleanly" do
      post door_sell_path(listing), params: { quantities: { general.id.to_s => "1" }, kind: "card" }
      order = listing.ticket_orders.sole

      get tickets_checkout_path(token: order.token)
      expect(response.body).to include("Pay at the door", "(optional)")
      expect(response.body).not_to include("Change tickets")

      order.update_columns(created_at: 1.minute.ago)
      intent = Stripe::PaymentIntent.construct_from(id: "pi_door", client_secret: "pi_door_secret", amount: 2_142, status: "requires_payment_method")
      allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)
      post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "", buyer_email: "" }, as: :json
      expect(response.parsed_body).to eq("client_secret" => "pi_door_secret")

      post door_card_cancel_path(listing, token: order.token)
      expect(flash[:notice]).to eq("Canceled. Nothing was charged.")
      expect(order.reload.status).to eq("expired")
      expect(listing.inventory.remaining(tier: general)).to eq(20)
    end

    it "keeps check-in-only people, and other theaters, away" do
      post door_sell_path(listing), params: { quantities: { general.id.to_s => "1" }, kind: "card" }
      order = listing.ticket_orders.sole

      other = create(:user, password: password)
      grant(other, "check_in")
      sign_in(other)
      get door_card_path(listing, token: order.token)
      expect(response).to redirect_to(door_path(listing))

      elsewhere = create(:ticket_listing, organization: create(:organization, :pro))
      get door_card_path(elsewhere, token: order.token)
      expect(response).to have_http_status(:not_found)
    end
  end
end
