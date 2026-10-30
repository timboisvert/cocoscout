# frozen_string_literal: true

require "rails_helper"

# Gift certificates end to end: a manager issues one (any show, or some
# productions and dates), a buyer types its code on the checkout page and it
# pays instead of the card, and the pages say how the order was paid.
RSpec.describe "Gift certificates", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:manager) { create(:user, email_address: "tim@example.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: manager) }
  let(:production) { create(:production, organization: org, name: "Late Night Cabaret") }
  let(:show) { create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 22)) }
  let!(:setup) do
    TicketingProfile.for(org).update!(enabled: true)
    ProductionTicketing.for(production)
  end
  let(:listing) { create(:ticket_listing, organization: org, show: show, slug: "late-night") }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_500, quantity: 20) }

  def sign_in_manager
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_path
  end

  def start_checkout
    TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "3" }).tap do |order|
      order.update!(buyer_name: "Dana Whitfield", buyer_email: "dana@example.com", created_at: 1.minute.ago)
    end
  end

  describe "the manager's page" do
    before { sign_in_manager }

    it "issues a certificate good for any show, shows its code once, and emails it" do
      expect {
        post manage_ticket_gift_certificates_path, params: {
          ticket_gift_certificate: { amount: "$50.00", recipient_name: "Dana Whitfield", recipient_email: "dana@example.com", note: "Raffle prize" },
          good_for: "any", email_it: "1"
        }
      }.to have_enqueued_job(TicketGiftCertificateEmailJob)
      certificate = org.ticket_gift_certificates.sole
      expect([ certificate.amount_cents, certificate.remaining_cents, certificate.scope, certificate.issued_by ]).to eq([ 5_000, 5_000, "any", manager ])
      expect(response).to redirect_to(manage_ticket_gift_certificates_path(issued: certificate.id, emailed: 1))

      follow_redirect!
      expect(response.body).to include("Gift certificate issued", certificate.code, "Copy code", "Raffle prize", "Unused", "Issue a gift certificate")

      perform_enqueued_jobs
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([ "dana@example.com" ])
      expect(mail.subject).to eq("A gift certificate from Stars & Garters")
      expect(mail.body.encoded).to include(certificate.code, "$50.00", "any show Stars &amp; Garters sells tickets to")
    end

    it "issues one good for some productions and dates" do
      follies = create(:production, organization: org, name: "Winter Follies")
      follies_show = create(:show, production: follies, date_and_time: 20.days.from_now.change(hour: 20))
      create(:ticket_listing, organization: org, show: follies_show)
      other_show = create(:show, production: production, date_and_time: 12.days.from_now.change(hour: 22))
      other_listing = create(:ticket_listing, organization: org, show: other_show)

      get manage_ticket_gift_certificates_path
      expect(response.body).to include("Only these", "Late Night Cabaret", "Winter Follies", "2 dates on sale")

      post manage_ticket_gift_certificates_path, params: {
        ticket_gift_certificate: { amount: "25" }, good_for: "some",
        productions: { production.id.to_s => { all: "1", listing_ids: [ listing.id.to_s ] }, follies.id.to_s => { all: "1" } }
      }
      certificate = org.ticket_gift_certificates.sole
      expect(certificate.scope).to eq("some")
      expect(certificate.scopes.map { |s| [ s.production_id, s.ticket_listing_id ] }).to contain_exactly([ production.id, listing.id ], [ follies.id, nil ])
      expect(certificate.covers?(other_listing)).to be(false)
      expect(certificate.good_for_words).to eq("Late Night Cabaret (1 date) and Winter Follies")
    end

    it "refuses 'only these' with nothing picked, and voids a code" do
      post manage_ticket_gift_certificates_path, params: { ticket_gift_certificate: { amount: "25" }, good_for: "some" }
      expect(flash[:alert]).to include("Pick at least one")
      expect(org.ticket_gift_certificates.count).to eq(0)

      certificate = org.ticket_gift_certificates.create!(amount_cents: 2_500)
      patch manage_ticket_gift_certificate_void_path(certificate)
      expect(certificate.reload.voided_by).to eq(manager)
      get manage_ticket_gift_certificates_path
      expect(response.body).to include("Voided")
    end
  end

  describe "the checkout page" do
    let!(:certificate) { org.ticket_gift_certificates.create!(amount_cents: 5_000, recipient_name: "Dana Whitfield") }
    let!(:order) { start_checkout }

    it "offers the code field under the total and applies a code in place" do
      get tickets_checkout_path(token: order.token)
      expect(response.body).to include("Have a gift certificate?", "Gift certificate code", "Pay $79.09")

      post tickets_checkout_gift_certificate_path(token: order.token), params: { code: certificate.code.downcase }, as: :json
      data = response.parsed_body
      expect([ data["total_cents"], data["card_cents"] ]).to eq([ 7_909, 2_909 ])
      expect(data["summary_html"]).to include("Gift certificate", certificate.code, "−$50.00", "Left to pay", "$29.09", "Remove")

      get tickets_checkout_path(token: order.token)
      expect(response.body).to include("Pay the rest · $29.09", "Pay $29.09")
      expect(response.body).not_to include("Have a gift certificate?\n")

      delete tickets_checkout_gift_certificate_path(token: order.token), as: :json
      expect(response.parsed_body["card_cents"]).to eq(7_909)
      expect(certificate.reload.remaining_cents).to eq(5_000)
    end

    it "answers a wrong code plainly, and makes a guesser wait" do
      post tickets_checkout_gift_certificate_path(token: order.token), params: { code: "GIFT-AAAA-BBBB-CCCC" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq(TicketGiftCertificates::WRONG_CODE)

      store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(store)
      TicketCheckoutsController::GIFT_MISSES_PER_HOUR.times do
        post tickets_checkout_gift_certificate_path(token: order.token), params: { code: "GIFT-AAAA-BBBB-CCCC" }, as: :json
      end
      post tickets_checkout_gift_certificate_path(token: order.token), params: { code: certificate.code }, as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["error"]).to include("wait an hour")
      expect(certificate.reload.remaining_cents).to eq(5_000)
    end

    it "pays the whole order with no card when the certificate covers it, and the pages say how it was paid" do
      big = org.ticket_gift_certificates.create!(amount_cents: 10_000)
      post tickets_checkout_gift_certificate_path(token: order.token), params: { code: big.code }, as: :json
      expect(response.parsed_body["card_cents"]).to eq(0)
      expect(response.parsed_body["summary_html"]).to include("$20.91 stays on the certificate")

      get tickets_checkout_path(token: order.token)
      expect(response.body).to include("Get my tickets")
      expect(response.body).not_to include("js.stripe.com")

      post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Dana Whitfield", buyer_email: "dana@example.com" }, as: :json
      expect(response.parsed_body["redirect"]).to eq(tickets_order_path(token: order.token))
      order.reload
      expect([ order.status, order.gift_certificate_cents, order.card_cents ]).to eq([ "paid", 7_909, 0 ])
      expect(big.reload.remaining_cents).to eq(2_091)

      get tickets_order_path(token: order.token)
      expect(response.body).to include("How you paid", "Gift certificate", big.code, "$79.09", "$20.91 is still on your gift certificate")

      get tickets_order_receipt_path(token: order.token)
      expect(response.body).to include("Paid with gift certificate")

      sign_in_manager
      get manage_ticket_order_path(order.id)
      expect(response.body).to include("Paid with gift certificate (#{big.code})", "Into your CocoScout balance", "−$1.50")
      get manage_ticket_gift_certificates_path
      expect(response.body).to include("$20.91 left", "spent on", "order #{order.code}")
    end

    it "hands the card only the rest when it pays some" do
      post tickets_checkout_gift_certificate_path(token: order.token), params: { code: certificate.code }, as: :json
      intent = Stripe::PaymentIntent.construct_from(id: "pi_rest", client_secret: "pi_rest_secret", amount: 2_909, status: "requires_payment_method")
      expect(Stripe::PaymentIntent).to receive(:create).with(hash_including(amount: 2_909), anything).and_return(intent)

      post tickets_checkout_pay_path(token: order.token), params: { buyer_name: "Dana Whitfield", buyer_email: "dana@example.com" }, as: :json
      expect(response.parsed_body["client_secret"]).to eq("pi_rest_secret")
    end
  end
end
