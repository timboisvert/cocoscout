# frozen_string_literal: true

require "rails_helper"

# Paying for a course on our own page: the hold, the checkout page with the
# shared partials, a free course finishing on the spot, a card payment through
# Stripe's intent, and the done page settling without the webhook.
RSpec.describe "Course checkout", type: :request do
  let(:org) { create(:organization, name: "Stars & Garters") }
  let(:production) { create(:production, organization: org, name: "Improv 101", production_type: "course") }
  let!(:offering) { create(:course_offering, production: production, title: "Improv 101", price_cents: 10_000, capacity: 12) }
  let!(:session_show) { create(:show, production: production, course_offering: offering, event_type: "class", date_and_time: Time.zone.local(2026, 11, 3, 19, 0), duration_minutes: 120) }
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, email: user.email_address, name: "Fox Mulder") }

  before do
    travel_to Time.zone.local(2026, 10, 4, 12, 0)
    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "8", mode: "added")
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  def start
    post my_course_checkout_path(code: offering.short_code)
    offering.course_registrations.order(:id).last
  end

  it "holds the spot and opens checkout with every cent named" do
    registration = start
    expect(response).to redirect_to(my_course_checkout_show_path(code: offering.short_code, token: registration.token))
    follow_redirect!
    expect(response.body).to include("Improv 101", "Tue, Nov 3 · 7:00 PM", "Course fee", "$100.00", "Sales tax 8%", "$8.00", "$108.00",
                                     "Registering as", "Fox Mulder", "Pay $108.00", "Back to the course", 'data-controller="checkout"',
                                     %(data-checkout-expires-at-value="#{registration.expires_at.iso8601}"))
    expect(response.body).not_to include("buyer_name")
  end

  it "sends a visitor to the course page first" do
    get signout_path
    post my_course_checkout_path(code: offering.short_code)
    expect(response).to redirect_to(my_course_entry_path(code: offering.short_code))
  end

  it "finishes a free course on the spot" do
    offering.update!(price_cents: 0)
    TicketTaxSetting.save!(org, kind: "courses", name: "Sales tax", percent: "0", mode: "added")
    registration = start
    travel 5.seconds
    post my_course_checkout_pay_path(code: offering.short_code, token: registration.token), as: :json
    expect(response.parsed_body["redirect"]).to eq(my_course_success_path(code: offering.short_code, token: registration.token))
    expect(registration.reload).to be_confirmed
    get my_course_success_path(code: offering.short_code, token: registration.token)
    expect(response.body).to include("Improv 101")
  end

  it "won't take a payment faster than a person could, or on a lapsed hold" do
    registration = start
    post my_course_checkout_pay_path(code: offering.short_code, token: registration.token), as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to include("try again")

    travel 5.seconds
    post my_course_checkout_pay_path(code: offering.short_code, token: registration.token), params: { website: "x" }, as: :json
    expect(response).to have_http_status(:unprocessable_content)

    registration.update!(expires_at: 1.minute.ago)
    post my_course_checkout_pay_path(code: offering.short_code, token: registration.token), as: :json
    expect(response.parsed_body["error"]).to include("ran out")
    get my_course_checkout_show_path(code: offering.short_code, token: registration.token)
    expect(response.body).to include("Your hold on your spot ran out")
  end

  it "creates one PaymentIntent for the total and settles on the done page" do
    registration = start
    travel 5.seconds
    intent = Stripe::PaymentIntent.construct_from(id: "pi_course", amount: 10_800, status: "requires_payment_method", client_secret: "pi_course_secret", latest_charge: nil)
    expect(Stripe::PaymentIntent).to receive(:create).with(hash_including(amount: 10_800, metadata: hash_including(type: "course_registration", course_registration_id: registration.id)), anything).and_return(intent)
    post my_course_checkout_pay_path(code: offering.short_code, token: registration.token), as: :json
    expect(response.parsed_body["client_secret"]).to eq("pi_course_secret")
    expect(registration.reload.stripe_payment_intent_id).to eq("pi_course")

    paid = Stripe::PaymentIntent.construct_from(id: "pi_course", amount: 10_800, status: "succeeded", latest_charge: "ch_course")
    allow(Stripe::PaymentIntent).to receive(:retrieve).with("pi_course").and_return(paid)
    allow(Stripe::Charge).to receive(:retrieve).with("ch_course").and_return(Stripe::Charge.construct_from(id: "ch_course", balance_transaction: "txn_1"))
    allow(Stripe::BalanceTransaction).to receive(:retrieve).with("txn_1").and_return(Stripe::BalanceTransaction.construct_from(id: "txn_1", fee: 343))
    get my_course_checkout_done_path(code: offering.short_code, token: registration.token)
    expect(response).to redirect_to(my_course_success_path(code: offering.short_code, token: registration.token))
    registration.reload
    expect(registration).to be_confirmed
    expect(registration.stripe_charge_id).to eq("ch_course")
    expect(registration.stripe_fee_cents).to eq(343)
    expect(registration.tax_lines.sum(:tax_cents)).to eq(800)
  end

  it "keeps a registration to its own person" do
    registration = start
    get signout_path
    other = create(:user, password: password)
    create(:person, user: other, email: other.email_address)
    post handle_signin_path, params: { email_address: other.email_address, password: password }
    get my_course_checkout_show_path(code: offering.short_code, token: registration.token)
    expect(response).to have_http_status(:not_found)
  end
end
