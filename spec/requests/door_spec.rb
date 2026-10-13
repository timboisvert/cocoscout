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
      expect(response.body).to include("Filter by name", ">List<", ">Scan<")
      expect(response.body).not_to include("At the door")
      # No credit pass covers this show, so the filter never asks for holders.
      expect(response.body).not_to include("passes_only")
    end

    it "shows door sales to box office and managers" do
      grant(door_person, "box_office")
      sign_in(door_person)
      get door_path(listing)
      expect(response.body).to include("Sell tickets", "Card or phone pay")
      # Sell sits beside List and Scan, and its form above the list, so a long
      # night's list never pushes it out of reach (Tim, 2026-10-11).
      body = response.body
      expect(body.index('data-mode="sell"')).to be < body.index('data-door-target="listPanel"')
      expect(body.index('data-door-target="sellPanel"')).to be < body.index('data-door-target="listPanel"')
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
      post door_check_in_path(listing), params: { code: "https://cocoscout.com/tickets/v/#{ticket.code}" }, as: :json
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

    # Most nights people are looked up by name: the list has everyone, a
    # box per party, and says who's a comp or a door sale.
    it "lists every party with a box that checks the whole party in" do
      order = sold_order(3)
      TicketDoor.new(listing, owner).sell({ general.id.to_s => "1" }, kind: "comp", buyer_name: "Abe Comp")
      get door_path(listing)
      expect(response.body).to include("Abe Comp", "1 General · Comp · In", "All in", "Dana Scully", "3 General", 'title="Check in all 3"',
                                       door_check_in_order_path(listing, order_id: order.id))
      expect(response.body.index("Abe Comp")).to be < response.body.index("Dana Scully")

      post door_check_in_path(listing), params: { code: order.tickets.first.code }, as: :json
      get door_list_path(listing)
      expect(response.body).to include(">1/3<", "1 of 3 in", 'title="Check in all 2"')
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

  # Tap to Pay: the buyer's card on the door phone itself, through the app's
  # Stripe Terminal SDK. The server holds the seats, makes the in-person
  # PaymentIntent, hands out connection tokens, and settles once Stripe says
  # paid — the same books as every other sale.
  describe "Tap to Pay (the app)" do
    let(:native) { { "User-Agent" => "Turbo Native iOS" } }

    before do
      grant(door_person, "box_office")
      sign_in(door_person)
    end

    it "won't sell by tap until the venue has an address for Stripe's Location" do
      org.locations.update_all(address1: nil)
      post door_sell_path(listing), params: { kind: "tap", quantities: { general.id => 2 } }
      expect(response).to redirect_to(door_path(listing))
      expect(flash[:alert]).to include("venue's address")
      expect(listing.ticket_orders.count).to eq(0)
    end

    context "with the venue's address" do
      let(:intent) do
        Stripe::PaymentIntent.construct_from(id: "pi_tap", client_secret: "pi_tap_secret", amount: 4_229,
                                             status: "requires_payment_method", latest_charge: nil)
      end

      before do
        org.locations.create!(name: "Playhouse", address1: "48 Lantern St", city: "Providence", state: "RI", postal_code: "02903", default: true)
        allow(Stripe::Terminal::Location).to receive(:create).and_return(Stripe::Terminal::Location.construct_from(id: "tml_1"))
        allow(Stripe::Terminal::ConnectionToken).to receive(:create).and_return(Stripe::Terminal::ConnectionToken.construct_from(secret: "pst_1"))
        allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)
      end

      it "offers the tap in the app only, priced at the in-person rate" do
        get door_path(listing)
        expect(response.body).not_to include("Tap to pay")

        get door_path(listing), headers: native
        expect(response.body).to include("Tap to pay", "data-door-sell-tap-per-mille-value=\"27\"", "data-door-sell-tap-fixed-value=\"15\"")
      end

      it "holds the seats behind an in-person PaymentIntent, and checks them in once Stripe says paid" do
        post door_sell_path(listing), params: { kind: "tap", quantities: { general.id => 2 }, buyer_name: "Robin" }, headers: native
        order = listing.ticket_orders.last
        expect(response).to redirect_to(door_tap_path(listing, token: order.token))
        expect(order).to have_attributes(channel: "door_tap", status: "pending", total_cents: 4_229, processing_cents: 129,
                                         org_net_cents: 4_000, stripe_payment_intent_id: "pi_tap", buyer_name: "Robin")
        expect(order.tickets.pluck(:status)).to eq(%w[reserved reserved])
        expect(org.reload.stripe_terminal_location_id).to eq("tml_1")
        expect(Stripe::PaymentIntent).to have_received(:create)
          .with(hash_including(amount: 4_229, payment_method_types: [ "card_present" ], transfer_group: "org_#{org.id}",
                               metadata: hash_including(ticket_order_id: order.id, terminal_location: "tml_1")), anything)

        get door_tap_path(listing, token: order.token), headers: native
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("$42.29", "pi_tap_secret", door_tap_settle_path(listing, token: order.token))

        # The app's Terminal SDK connects with a token at the organization's Location — made once.
        2.times { get door_tap_connection_token_path(listing), headers: native }
        expect(response.parsed_body).to eq("secret" => "pst_1")
        expect(Stripe::Terminal::ConnectionToken).to have_received(:create).with(location: "tml_1").twice
        expect(Stripe::Terminal::Location).to have_received(:create).once

        # Too soon: Stripe hasn't confirmed, nothing settles.
        post door_tap_settle_path(listing, token: order.token), headers: native
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("hasn't confirmed")
        expect(order.reload.status).to eq("pending")

        paid = Stripe::PaymentIntent.construct_from(id: "pi_tap", amount: 4_229, status: "succeeded", latest_charge: "ch_tap")
        allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(paid)
        post door_tap_settle_path(listing, token: order.token), headers: native
        expect(response.parsed_body).to include("status" => "paid", "message" => "2 tickets paid by card, checked in.")
        expect(order.reload).to have_attributes(status: "paid", stripe_charge_id: "ch_tap")
        expect(order.tickets.pluck(:status).uniq).to eq([ "checked_in" ])
        expect(OrgCashEntry.where(organization: org).sum(:amount_cents)).to eq(4_000)

        # Settling again, or the door asking how it stands, says paid and changes nothing.
        post door_tap_settle_path(listing, token: order.token), headers: native
        expect(response.parsed_body["status"]).to eq("paid")
        get door_card_status_path(listing, token: order.token), headers: native
        expect(response.parsed_body["status"]).to eq("paid")
        expect(OrgCashEntry.where(organization: org).count).to eq(1)
      end

      it "needs box office, like every sale" do
        org.ticketing_access_grants.find_by(user: door_person).update!(access_level: "check_in")
        get door_tap_connection_token_path(listing), headers: native.merge("Accept" => "application/json")
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
