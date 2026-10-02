# frozen_string_literal: true

require "rails_helper"

# The public box office at /t: a theater's shows, a show's page with all-in
# prices, checkout with no sign-in, and the buyer's tickets at a private link.
RSpec.describe "Public ticketing", type: :request do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let!(:profile) { TicketingProfile.for(org).tap { |p| p.update!(enabled: true, slug: "starsandgarters") } }
  let(:production) { create(:production, organization: org, name: "Improvised Animorphs", description: "Every scene turns into an animal.") }
  let(:show) { create(:show, production: production, date_and_time: 5.days.from_now.change(hour: 19, min: 30)) }
  let!(:listing) { TicketListing.create!(show: show, status: "on_sale") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60) }

  def event_path
    tickets_event_path(org: "starsandgarters", event: listing.slug)
  end

  def buy(count = 2, code: nil)
    post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug),
         params: { quantities: { general.id => count }, code: code }
    TicketOrder.order(:id).last
  end

  describe "the box office" do
    it "lists what's on sale, with the lowest all-in price" do
      draft = TicketListing.create!(show: create(:show, production: production, date_and_time: 6.days.from_now))
      get tickets_box_office_path(org: "starsandgarters")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Stars &amp; Garters").and include("From $21.42").and include(event_path)
      expect(response.body).not_to include(draft.slug)
    end

    it "stays hidden until ticketing is switched on, except for a superadmin's preview" do
      profile.update!(enabled: false)
      get tickets_box_office_path(org: "starsandgarters")
      expect(response).to have_http_status(:not_found)

      admin = create(:user, email_address: "boisvert@gmail.com", password: "Password123!")
      post handle_signin_path, params: { email_address: admin.email_address, password: "Password123!" }
      get tickets_box_office_path(org: "starsandgarters")
      expect(response.body).to include("Preview — not public yet")
    end

    it "has a page for each production's dates" do
      get tickets_production_path(org: "starsandgarters", production: production.id)
      expect(response.body).to include("Every scene turns into an animal.").and include(event_path)
    end
  end

  describe "a show's page" do
    it "prices every ticket all-in and tells search engines about the show" do
      get event_path
      expect(response.body).to include("$21.42").and include("incl. fees")
      expect(response.body).to include('"@type":"Event"').and include('"price":"21.42"')
    end

    it "shows a hidden tier only with its code" do
      listing.ticket_tiers.create!(name: "Industry", price_cents: 1_000, hidden: true, unlock_code: "INDUSTRY")
      get event_path
      expect(response.body).not_to include("Industry")

      get event_path, params: { code: "industry" }
      expect(response.body).to include("Industry")
    end

    it "says so when it's sold out, or not on sale" do
      listing.update!(status: "paused")
      get event_path
      expect(response.body).to include("Not on sale right now")
      expect(response.body).not_to include("Get tickets")
    end
  end

  describe "buying" do
    it "holds the seats and opens checkout with every cent named" do
      order = buy(2)
      expect(response).to redirect_to(tickets_checkout_path(token: order.token))

      follow_redirect!
      expect(response.body).to include("2 × General").and include("Service and card fees").and include("$2.53").and include("Pay $42.53")
    end

    it "sends a buyer back to the page with a reason when it can't" do
      post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { general.id => 0 } }
      expect(response).to redirect_to(event_path)
      expect(flash[:alert]).to eq("Pick at least one ticket.")
    end

    it "creates the PaymentIntent only once the buyer's details are in, and reuses it" do
      order = buy(2)
      intent = Stripe::PaymentIntent.construct_from(id: "pi_123", client_secret: "pi_123_secret", amount: 4_253, status: "requires_payment_method")
      allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)
      allow(Stripe::PaymentIntent).to receive(:retrieve).and_return(intent)

      travel 5.seconds do
        post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "", buyer_email: "nope" }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(Stripe::PaymentIntent).not_to have_received(:create)

        post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Avery Buyer", buyer_email: "Avery@Example.com" }, as: :json
        expect(response.parsed_body).to eq("client_secret" => "pi_123_secret")
        expect(Stripe::PaymentIntent).to have_received(:create).with(
          hash_including(amount: 4_253, currency: "usd", metadata: hash_including(type: "ticket_order", ticket_order_id: order.id)),
          hash_including(:idempotency_key)
        )
        expect(order.reload.attributes.slice("buyer_name", "buyer_email", "stripe_payment_intent_id"))
          .to eq("buyer_name" => "Avery Buyer", "buyer_email" => "avery@example.com", "stripe_payment_intent_id" => "pi_123")

        post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Avery Buyer", buyer_email: "avery@example.com" }, as: :json
        expect(Stripe::PaymentIntent).to have_received(:create).once
      end
    end

    it "turns away scripts: a filled-in honeypot, or paying faster than a person could" do
      allow(Stripe::PaymentIntent).to receive(:create)

      post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug),
           params: { quantities: { general.id => 2 }, website: "http://spam.example" }
      expect(response).to redirect_to(tickets_event_path(org: "starsandgarters", event: listing.slug))
      expect(TicketOrder.count).to eq(0)

      order = buy(1)
      post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Avery", buyer_email: "avery@example.com" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      travel 5.seconds do
        post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Avery", buyer_email: "avery@example.com", website: "x" }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(Stripe::PaymentIntent).not_to have_received(:create)
      expect(order.reload.buyer_email).to be_nil
    end

    it "settles when the buyer comes back from Stripe, and shows their tickets" do
      order = buy(1)
      order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com", stripe_payment_intent_id: "pi_123")
      allow(Stripe::PaymentIntent).to receive(:retrieve)
        .and_return(Stripe::PaymentIntent.construct_from(id: "pi_123", status: "succeeded", latest_charge: "ch_1", amount: 2_142))

      get tickets_checkout_done_path(token: order.token)
      expect(response).to redirect_to(tickets_order_path(token: order.token))
      expect(order.reload.status).to eq("paid")

      follow_redirect!
      expect(response.body).to include("You're going!").and include("<svg").and include("Add to calendar")
    end

    it "finishes a free order without Stripe" do
      free = listing.ticket_tiers.create!(name: "Comp", price_cents: 0)
      post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug), params: { quantities: { free.id => 1 } }
      order = TicketOrder.last
      allow(Stripe::PaymentIntent).to receive(:create)

      travel 5.seconds do
        post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Avery", buyer_email: "avery@example.com" }, as: :json
      end
      expect(response.parsed_body).to eq("redirect" => tickets_order_path(token: order.token))
      expect(order.reload.status).to eq("paid")
      expect(Stripe::PaymentIntent).not_to have_received(:create)
    end

    it "turns away a checkout whose hold ran out" do
      order = buy(1)
      travel 11.minutes do
        get tickets_checkout_path(token: order.token)
        expect(response.body).to include("Your hold on these seats ran out")

        post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Avery", buyer_email: "avery@example.com" }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "choosing tickets (layout A)" do
    it "lists each ticket type with steppers that carry its price, tax and limit" do
      TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      page = response.body
      expect(page).to include('data-controller="ticket-picker"', 'data-ticket-picker-fee-mode-value="buyer"',
                              "data-price=\"2000\"", "data-tax=\"205\"", "name=\"quantities[#{general.id}]\"",
                              "One more General", "Continue to checkout", "Prices include fees.", "The total includes tax.")
      expect(page).not_to include("<select")
    end
  end

  describe "the payment webhook" do
    it "settles the order Stripe says was paid" do
      order = buy(1)
      order.update!(buyer_email: "avery@example.com", stripe_payment_intent_id: "pi_hook")
      intent = Stripe::PaymentIntent.construct_from(id: "pi_hook", latest_charge: "ch_hook", amount: 2_142,
                                                    metadata: { type: "ticket_order", ticket_order_id: order.id.to_s })
      event = Stripe::Event.construct_from(id: "evt_ticket", type: "payment_intent.succeeded", data: { object: intent })
      allow_any_instance_of(StripeWebhooksController).to receive(:webhook_secrets).and_return([ "whsec_test" ])
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event)

      post "/webhooks/stripe", params: "{}", headers: { "HTTP_STRIPE_SIGNATURE" => "sig" }
      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("paid")
      expect(order.stripe_charge_id).to eq("ch_hook")
    end
  end

  describe "a buyer's order" do
    it "lives at its private link, sends tickets again, and adds to calendar" do
      order = buy(1)
      order.update!(buyer_email: "avery@example.com")
      TicketOrderSettlement.settle!(order)

      get tickets_order_calendar_path(token: order.token)
      expect(response.media_type).to eq("text/calendar")
      expect(response.body).to include("BEGIN:VEVENT").and include("SUMMARY:")

      expect { post tickets_order_resend_path(token: order.token) }.to have_enqueued_job(TicketOrderConfirmationJob)
    end

    it "emails the tickets with a QR code each" do
      order = buy(2)
      order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
      TicketOrderSettlement.settle!(order)

      mail = TicketOrderMailer.confirmation(order.reload)
      expect(mail.to).to eq([ "avery@example.com" ])
      expect(mail.subject).to include(listing.display_title)
      expect(mail[:from].display_names).to eq([ "Stars & Garters via CocoScout" ])
      expect(mail.attachments.map(&:filename).grep(/\Aticket-/).size).to eq(2)
    end

    it "lets a phone camera open a ticket from its QR code" do
      order = buy(1)
      TicketOrderSettlement.settle!(order)
      get tickets_ticket_path(code: order.tickets.sole.code)
      expect(response.body).to include(listing.display_title).and include("Order #{order.code}")
    end
  end
end
