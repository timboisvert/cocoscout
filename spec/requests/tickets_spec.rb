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

    # The production's page is where most people buy: pick a date, then that
    # date's tickets, on one page (R3-C).
    it "has a page for each production's dates, at its public key, never its id" do
      later = create(:show, production: production, date_and_time: 12.days.from_now.change(hour: 19, min: 30))
      later_listing = TicketListing.create!(show: later, status: "on_sale")
      later_listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 1)
      create(:ticket, ticket_order: create(:ticket_order, ticket_listing: later_listing, status: "paid", expires_at: nil),
                      ticket_tier: later_listing.ticket_tiers.first)

      get tickets_event_path(org: "starsandgarters", event: production.public_key)
      page = response.body
      expect(page).to include("Every scene turns into an animal.", 'aria-label="Pick a date"', "Sold out", "Continue to checkout",
                              %(name="quantities[#{general.id}]"), show.date_and_time.strftime("%A, %B %-d · %-l:%M %p"))
      expect(page).to include(%(href="/tickets/starsandgarters/#{production.public_key}?date=#{later_listing.slug}"))
      expect(production.public_key).to be_present

      get tickets_event_path(org: "starsandgarters", event: production.public_key, date: later.date_and_time.to_date.iso8601)
      expect(response.body).to include(later.date_and_time.strftime("%A, %B %-d · %-l:%M %p"), "Sold out")
      expect(response.body).not_to include("Continue to checkout")

      get event_path
      expect(response.body).to include(%(href="/tickets/starsandgarters/#{production.public_key}"))
      expect(response.body).not_to include("/p/#{production.id}")

      get tickets_event_path(org: "starsandgarters", event: production.id.to_s)
      expect(response).to have_http_status(:not_found)

      # One date needs no picking: the chips stay hidden.
      later_listing.update!(status: "draft")
      get tickets_event_path(org: "starsandgarters", event: production.public_key)
      expect(response.body).to include(%(class="flex flex-wrap justify-center gap-2 hidden" aria-label="Pick a date"), "Continue to checkout")
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
      expect(response.body).to include("Industry", "Your code <span class=\"font-medium uppercase\">INDUSTRY</span> is applied")
    end

    # A code is checked the moment it's entered, not at checkout: one for
    # another production, or a made-up one, says so and isn't applied.
    it "refuses a code that doesn't work for this show as soon as it's entered" do
      other = create(:production, organization: org, name: "Something Else")
      org.ticket_discount_codes.create!(production: other, code: "ELSEWHERE", kind: "percent", percent: 10)
      org.ticket_discount_codes.create!(production: production, code: "FRIENDS", kind: "percent", percent: 10)

      get event_path, params: { code: "elsewhere" }
      expect(response.body).to include("That code doesn&#39;t work for this show.")
      expect(response.body).not_to include("is applied")
      expect(response.body).not_to include('name="code" id="code" value="ELSEWHERE"')

      get event_path, params: { code: "friends" }
      expect(response.body).to include("Your code <span class=\"font-medium uppercase\">FRIENDS</span> is applied")
      expect(response.body).not_to include("doesn&#39;t work")
    end

    # "Only N left" from 5 unless the production says otherwise, and a date
    # can say otherwise again.
    it "says Only N left from the threshold the theater set" do
      general.update!(quantity: 8)
      get event_path
      expect(response.body).not_to include("Only 8 left")

      setup = ProductionTicketing.for(production)
      setup.update!(low_stock_threshold: 10)
      get event_path
      expect(response.body).to include("Only 8 left")

      TicketListing.find(listing.id).update!(low_stock_threshold: 3)
      get event_path
      expect(response.body).not_to include("Only 8 left")
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
      expect(response.body).to include("2 × General", ">Fees<", "$2.53", "Pay $42.53", "Change tickets")
    end

    # Courses pay on Stripe's page and need only the secret key; this page
    # needs the publishable key too. When it's missing, a buyer sees the JS's
    # plain line, and whoever can fix it sees the reason.
    it "tells a superadmin, not a buyer, when the publishable key isn't set" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("STRIPE_PUBLISHABLE_KEY").and_return(nil)
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:stripe, :publishable_key).and_return(nil)
      allow(Rails.env).to receive(:development?).and_return(false)

      order = buy(1)
      get tickets_checkout_path(token: order.token)
      expect(response.body).not_to include("publishable key isn't set")

      admin = create(:user, email_address: "boisvert@gmail.com", password: "Password123!")
      post handle_signin_path, params: { email_address: admin.email_address, password: "Password123!" }
      get tickets_checkout_path(token: order.token)
      expect(response.body).to include("publishable key isn't set", "STRIPE_PUBLISHABLE_KEY", "docs/dev_setup_stripe.md")
    end

    it "keeps the hold when the buyer goes back: the page can ask about it, and the same tickets reuse it" do
      order = buy(2)
      get tickets_checkout_hold_path(token: order.token)
      expect(response.parsed_body).to include("holding" => true, "listing_id" => listing.id, "quantities" => { general.id.to_s => 2 })

      get event_path
      expect(response.body).to include('data-ticket-picker-target="holdInput"', %(data-tier-id="#{general.id}"),
                                       tickets_checkout_hold_path(token: "TOKEN"))

      post tickets_start_checkout_path(org: "starsandgarters", event: listing.slug),
           params: { quantities: { general.id => 2 }, hold: order.token }
      expect(response).to redirect_to(tickets_checkout_path(token: order.token))
      expect(TicketOrder.count).to eq(1)

      order.update!(expires_at: 1.minute.ago)
      get tickets_checkout_hold_path(token: order.token)
      expect(response.parsed_body).to include("holding" => false, "quantities" => {})
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
                              'data-ticket-picker-tax-label-value="Sales tax 10.25%"', 'data-ticket-picker-target="breakdown"',
                              "data-price=\"2000\"", "data-tax=\"205\"", "name=\"quantities[#{general.id}]\"",
                              "One more General", "Continue to checkout")
      expect(page).not_to include("<select")
    end

    # Tim (2026-10-01): the price on each ticket is what one really costs —
    # fees and tax in — so the total never jumps above it.
    # And a tap on the price opens what it's made of (Tim, 2026-10-02),
    # with no footer repeating it.
    it "shows each ticket's real price, fees and tax in, and what it's made of on a tap" do
      panel = ->(body) { body[%r{<details class="mt-0.5">.*?</details>}m].to_s.gsub(/\s+/, " ") }

      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).to include("$21.42", "incl. fees")
      expect(panel.call(response.body)).to include("<dt>Ticket</dt>", "$20.00", "<dt>Fees</dt>", "$1.42", "<dt>One ticket</dt>")
      expect(response.body).not_to include("Prices include")

      TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).to include("$23.53", "incl. fees &amp; tax")
      expect(panel.call(response.body)).to include("$20.00", "<dt>Fees</dt>", "$1.48", "<dt>Sales tax</dt>", "$2.05", "$23.53")

      listing.update!(fee_mode: "org")
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).to include("$22.05", "incl. tax")
      expect(panel.call(response.body)).to include("$20.00", "<dt>Sales tax</dt>", "$2.05")
      expect(panel.call(response.body)).not_to include("Fees")

      TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "included")
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(response.body).to include("$20.00", "incl. tax")
      expect(panel.call(response.body)).to include("$18.14", "<dt>Sales tax</dt>", "$1.86", "$20.00")

      TicketTaxSetting.save!(org, name: "", percent: "", mode: "added")
      get tickets_event_path(org: "starsandgarters", event: listing.slug)
      expect(panel.call(response.body)).to be_empty
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

    # The confirmation is the receipt too, and every buyer email says where
    # questions go (the theater, which is also the reply-to).
    it "puts what they paid on the confirmation, and the theater's address under every email" do
      profile.update!(support_email: "box@starsandgarters.com")
      order = buy(2)
      order.update!(buyer_name: "Avery Buyer", buyer_email: "avery@example.com")
      TicketOrderSettlement.settle!(order)

      html = TicketOrderMailer.confirmation(order.reload).html_part.body.to_s
      expect(html).to include("What you paid", "2 × General", "$40.00", ">Fees<", "$2.53", "$42.53", "paid ", "Questions about your order?", "box@starsandgarters.com")
      expect(TicketOrderMailer.confirmation(order).reply_to).to eq([ "box@starsandgarters.com" ])
    end

    it "lets a phone camera open a ticket from its QR code" do
      order = buy(1)
      TicketOrderSettlement.settle!(order)
      get tickets_ticket_path(code: order.tickets.sole.code)
      expect(response.body).to include(listing.display_title).and include("Order #{order.code}")
    end
  end
end
