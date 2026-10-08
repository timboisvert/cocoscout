# frozen_string_literal: true

require "rails_helper"

# Round 10 (2026-10-07): the box office declares a refund policy (24 hours
# before the show by default, fees kept by default), a production can set
# its own, buyers see it before they pay, and the refund screen knows
# whether a refund is within it; outside it, Refund anyway.
RSpec.describe "Refund policy", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters", support_email: "box@sg.example") } }
  let(:production) { create(:production, organization: org, name: "Boylesque") }
  let(:show_at) { Time.zone.local(2026, 11, 6, 21, 0) }
  let(:show) { create(:show, production: production, date_and_time: show_at) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  before do
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
    create(:organization_role, :manager, user: owner, organization: org)
  end

  def sign_in
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  def sold(on = listing, tier = general)
    order = TicketCheckout.start!(listing: on, quantities: { tier.id.to_s => "1" })
    order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{SecureRandom.hex(4)}")
    order.reload
  end

  it "defaults to 24 hours before, fees kept, and the box office's Refunds tab changes it" do
    expect(RefundPolicy.for(listing)).to have_attributes(kind: "window", hours: 24, fees: false)
    sign_in

    get manage_ticketing_settings_section_path(section: "box_office")
    expect(response.body).to include(manage_ticketing_settings_section_path(section: "refunds"))
    expect(response.body).not_to include("Up to 24 hours before")

    get manage_ticketing_settings_section_path(section: "refunds")
    expect(response.body).to include("Refund policy", "Up to 24 hours before", "No refunds", "Case by case",
                                     "Buyers see:</span> Refunds up to 24 hours before the show. Fees aren&#39;t refunded.")

    patch manage_ticketing_settings_refunds_path, params: { ticketing_profile: { refund_choice: "custom", refund_days: "10", refund_fees: "1", refund_policy_note: "Exchanges welcome." } }
    expect(response).to redirect_to(manage_ticketing_settings_section_path(section: "refunds"))
    expect(profile.reload).to have_attributes(refund_policy: "window", refund_window_hours: 240, refund_fees: true, refund_policy_note: "Exchanges welcome.")
    expect(RefundPolicy.for(listing.reload).words).to eq("Refunds up to 10 days before the show. Fees are refunded too. If a show is canceled, you get everything back. Exchanges welcome.")

    patch manage_ticketing_settings_refunds_path, params: { ticketing_profile: { refund_choice: "none", refund_fees: "0", refund_policy_note: "x" * 501 } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "lets a production set its own, and go back to the box office's" do
    setup = ProductionTicketing.for(production)
    sign_in

    get manage_edit_production_ticketing_path(production, section: "sales")
    expect(response.body).to include(manage_edit_production_ticketing_path(production, section: "refunds"))
    expect(response.body).not_to include("follows your box office")

    get manage_edit_production_ticketing_path(production, section: "refunds")
    expect(response.body).to include("Refund policy", "Boylesque follows your box office's: refunds up to 24 hours before the show")

    patch manage_update_production_ticketing_path(production, section: "refunds"),
          params: { production_ticketing: { own_refund_policy: "1", refund_choice: "none", refund_fees: "0" } }
    expect(flash[:notice]).to eq("Saved. Boylesque has its own refund policy.")
    expect(setup.reload.refund_policy).to eq("none")
    expect(RefundPolicy.for(TicketListing.find(listing.id)).kind).to eq("none")

    patch manage_update_production_ticketing_path(production, section: "refunds"), params: { production_ticketing: { own_refund_policy: "0" } }
    expect(flash[:notice]).to eq("Saved. Boylesque follows your box office's refund policy.")
    expect(setup.reload.refund_policy).to be_nil
    expect(RefundPolicy.for(TicketListing.find(listing.id)).kind).to eq("window")
  end

  describe "the check" do
    it "is within the window until it ends, then outside, and holds the order to the more generous policy" do
      order = travel_to(show_at - 3.days) { sold }
      expect(order.refund_policy).to include("kind" => "window", "hours" => 24)

      check = TicketOrderRefund.policy_check(order, at: show_at - 2.days)
      expect(check).to have_attributes(within: true, deadline: show_at - 24.hours)

      late = TicketOrderRefund.policy_check(order, at: show_at - 12.hours)
      expect(late.within).to be(false)
      expect(late.reason).to eq("Refunds ended Thu, Nov 5, 9:00 PM (24 hours before the show)")

      # A stricter policy later doesn't apply to tickets already sold; a looser one does.
      profile.update!(refund_policy: "none")
      expect(TicketOrderRefund.policy_check(order.reload, at: show_at - 2.days).within).to be(true)
      profile.update!(refund_policy: "window", refund_window_hours: 0)
      expect(TicketOrderRefund.policy_check(order.reload, at: show_at - 12.hours).within).to be(true)
    end

    it "moves the window with the show, and is outside once the show has happened" do
      order = travel_to(show_at - 3.days) { sold }
      show.update!(date_and_time: show_at + 2.days)
      expect(TicketOrderRefund.policy_check(order.reload, at: show_at + 12.hours).within).to be(true)
      expect(TicketOrderRefund.policy_check(order, at: show_at + 3.days).reason).to eq("The show has happened")
    end

    it "says all sales are final, or leaves it to the manager, as the policy says; comps are always free to cancel" do
      profile.update!(refund_policy: "none")
      order = travel_to(show_at - 3.days) { sold }
      expect(TicketOrderRefund.policy_check(order, at: show_at - 2.days)).to have_attributes(within: false, reason: "All sales are final")

      profile.update!(refund_policy: "case_by_case")
      other = travel_to(show_at - 3.days) { sold }
      expect(TicketOrderRefund.policy_check(other, at: show_at - 1.hour).within).to be(true)

      comp = TicketComps.give!(listing, [ TicketComps::Guest.new(name: "W", email: nil, tier: general, quantity: 1) ], by: owner, email_them: false).first
      profile.update!(refund_policy: "none")
      expect(TicketOrderRefund.policy_check(comp, at: show_at - 2.days).within).to be(true)
    end
  end

  describe "refunding" do
    it "says where a refund stands, starts from the policy's fee choice, and refunds within policy without a toggle" do
      order = travel_to(show_at - 3.days) { sold }
      sign_in
      travel_to(show_at - 2.days) do
        get manage_ticket_order_path(order.id)
        expect(response.body).to include("Within the refund policy</span> until Thu, Nov 5, 9:00 PM")
        expect(response.body).to match(/<input type="checkbox" name="keep_fees" id="keep_fees" value="1"[^>]*checked="checked"/)

        get manage_ticket_order_refund_path(order.id), params: { ticket_ids: order.tickets.pluck(:id) }
        expect(response.body).to include("Fees they paid</dt><dd>Kept</dd>")
        expect(response.body).not_to include("Refund anyway")

        post manage_ticket_order_refund_path(order.id), params: { ticket_ids: order.tickets.pluck(:id), keep_fees: "1", reason: "Can't make it" }
        refund = order.reload.ticket_refunds.sole
        expect(refund).to have_attributes(outside_policy: false, keep_fees: true, policy_words: start_with("Refunds up to 24 hours before the show."))
      end
    end

    it "needs Refund anyway past the window, and marks the refund as an exception" do
      order = travel_to(show_at - 3.days) { sold }
      sign_in
      travel_to(show_at - 12.hours) do
        get manage_ticket_order_path(order.id)
        expect(response.body).to include("Outside the refund policy:</span> Refunds ended Thu, Nov 5, 9:00 PM (24 hours before the show).")
        get manage_ticket_order_refund_path(order.id), params: { ticket_ids: order.tickets.pluck(:id) }
        expect(response.body).to include("Outside the refund policy", "Refund anyway", 'name="outside_policy"', "<fieldset disabled")

        post manage_ticket_order_refund_path(order.id), params: { ticket_ids: order.tickets.pluck(:id), keep_fees: "1", outside_policy: "1", reason: "Flight canceled" }
        expect(order.reload.status).to eq("refunded")
        expect(order.ticket_refunds.sole).to have_attributes(outside_policy: true, reason: "Flight canceled")
        get manage_ticket_order_path(order.id)
        expect(response.body).to include("Outside the refund policy · Flight canceled")
      end
    end

    it "moves tickets of a show that has happened only with Move anyway" do
      later_show = create(:show, production: production, date_and_time: show_at + 7.days)
      later = TicketListing.create!(show: later_show, status: "on_sale")
      later.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
      order = travel_to(show_at - 3.days) { sold }
      sign_in
      travel_to(show_at + 2.hours) do
        get manage_ticket_order_exchange_path(order.id), params: { to_listing_id: later.id }
        expect(response.body).to include("Move anyway")

        post manage_ticket_order_exchange_path(order.id), params: { to_listing_id: later.id, ticket_ids: order.tickets.pluck(:id) }
        expect(flash[:alert]).to include("Turn on Move anyway")
        post manage_ticket_order_exchange_path(order.id), params: { to_listing_id: later.id, ticket_ids: order.tickets.pluck(:id), outside_policy: "1" }
        expect(flash[:notice]).to start_with("Moved 1 ticket")
      end
    end
  end

  describe "buyers" do
    it "see the policy on the ticket page, at checkout, on their order and in their email" do
      travel_to(show_at - 3.days) do
        get tickets_event_path(org: "starsandgarters", event: listing.slug)
        # Its own box at the foot of the page, after the checkout button and About.
        body = response.body
        expect(body).to include("Refund policy</h2>", "Refunds up to 24 hours before the show. Fees aren&#39;t refunded.")
        expect(body.index("Refund policy</h2>")).to be > body.index("Continue to checkout")

        post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { general.id => 1 } }
        order = TicketOrder.order(:id).last
        get tickets_checkout_path(token: order.token)
        expect(response.body).to include("Refund policy:</span> Refunds up to 24 hours before the show. Fees aren&#39;t refunded.")

        order.update!(buyer_name: "Dana Scully", buyer_email: "dana@example.com")
        TicketOrderSettlement.settle!(order, payment_intent_id: "pi_buyer")
        get tickets_order_path(token: order.token)
        expect(response.body).to include("Refund policy", "To ask for a refund, reply to your confirmation email.")

        mail = TicketOrderMailer.confirmation(order.reload)
        expect(mail.html_part&.body.to_s.presence || mail.body.to_s).to include("<strong>Refund policy:</strong> Refunds up to 24 hours before the show.")
      end
    end
  end
end
