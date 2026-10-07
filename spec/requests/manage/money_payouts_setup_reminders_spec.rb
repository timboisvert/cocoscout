# frozen_string_literal: true

require "rails_helper"

# The production payouts page's Send Reminders, brought in line with a
# show's (Tim, 2026-10-07): the shared draft modal lists who gets it, and
# the send uses the edited subject and message. Before, the edits were
# thrown away and the stock template went out with {{production_name}}
# unfilled.
RSpec.describe "Production payouts: payment setup reminders", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars & Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org, name: "Boylesque") }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
  let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 200) }
  let(:ollie) { create(:person, name: "Ollie Owed", email: "ollie@example.com", user: create(:user, email_address: "ollie@example.com")) }
  let(:nolan) { create(:person, name: "Nolan Nologin", email: "nolan@example.com") }

  before do
    ShowPayoutLineItem.create!(show_payout: payout, payee: ollie, amount: 120)
    ShowPayoutLineItem.create!(show_payout: payout, payee: nolan, amount: 30)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "opens the shared draft: who gets it, who it can't reach, the subject and message" do
    get manage_money_production_payouts_path(production)

    body = response.body
    expect(body).to include(%(data-modal-id="payment-reminders-modal"), "Remind them to set up payment", "Sending to 1 person", "Ollie Owed", "ollie@example.com")
    expect(body).to include(%(id="payment-reminders-modal-person-#{ollie.id}"), "Nolan Nologin doesn&#39;t have a CocoScout login yet")
    expect(body).not_to include(%(id="payment-reminders-modal-person-#{nolan.id}"), "notify-modal")
    expect(body).not_to match(/<form[^>]*send_payment_setup_reminders[^>]*>(?:(?!<\/form>).)*<form/m)
  end

  it "sends the edited copy, filled in per person, only to the people still ticked" do
    expect {
      post manage_send_payment_setup_reminders_money_payouts_path(production), params: {
        person_ids: [ ollie.id.to_s, nolan.id.to_s ],
        subject: "Hi {{first_name}}, you're owed for {{production_name}}",
        body: "<p>{{first_name}}, set up at {{payment_setup_url}}</p>"
      }
    }.to change(Message, :count).by(1)

    expect(flash[:notice]).to eq("Payment setup reminders sent to 1 person.")
    message = Message.order(:id).last
    expect(message.subject).to eq("Hi Ollie, you're owed for Boylesque")
    expect(message.body.to_s).to include("Ollie, set up at", "/my/payments")
    expect(message.body.to_s).not_to include("{{")
  end

  it "sends nothing when nobody is ticked or the draft is empty" do
    expect {
      post manage_send_payment_setup_reminders_money_payouts_path(production), params: { subject: "Hi", body: "<p>Hi</p>" }
    }.not_to change(Message, :count)
    expect(flash[:alert]).to eq("Nobody was ticked, so nothing was sent.")

    expect {
      post manage_send_payment_setup_reminders_money_payouts_path(production), params: { person_ids: [ ollie.id.to_s ], subject: " ", body: "<p>Hi</p>" }
    }.not_to change(Message, :count)
    expect(flash[:alert]).to eq("The reminder needs a subject and a message.")
  end
end
