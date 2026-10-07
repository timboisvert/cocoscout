# frozen_string_literal: true

require "rails_helper"

# Tim, 2026-10-07: "Send Reminders" on a show's payouts page sent straight
# away. Now it opens the draft: who gets it, what each is owed, the subject
# and message to edit, and only then sends, the edited copy, to the people
# still ticked.
RSpec.describe "Show payouts: payment setup reminders", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, owner: owner, name: "Stars & Garters") }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }
  let!(:show) { create(:show, production: production, event_type: :show, date_and_time: 3.days.ago) }
  let!(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 200) }
  let(:ollie) { create(:person, name: "Ollie Owed", email: "ollie@example.com", user: create(:user, email_address: "ollie@example.com")) }
  let(:pat) { create(:person, name: "Pat Present", email: "pat@example.com", user: create(:user, email_address: "pat@example.com")) }
  let(:nolan) { create(:person, name: "Nolan Nologin", email: "nolan@example.com") }

  before do
    ShowPayoutLineItem.create!(show_payout: payout, payee: ollie, amount: 120)
    ShowPayoutLineItem.create!(show_payout: payout, payee: pat, amount: 45.5)
    ShowPayoutLineItem.create!(show_payout: payout, payee: nolan, amount: 30)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  it "opens a draft instead of sending: the people, what each is owed, the subject and message" do
    expect {
      get manage_money_show_payout_path(show)
    }.not_to change(Message, :count)

    body = response.body
    expect(body).to include("Remind them to set up payment", "Sending to 2 people", "Ollie Owed", "ollie@example.com", "$120.00", "$45.50")
    expect(body).to include("You have {{amount}} ready to be paid by Stars &amp; Garters", "{{recipient_name}}")
    expect(body).to include("Nolan Nologin", "have a CocoScout login yet")
    expect(body).to include(%(id="setup-reminders-modal-person-#{ollie.id}"))
    expect(body).not_to include(%(id="setup-reminders-modal-person-#{nolan.id}"))
    expect(body).to include(%(data-modal-id="setup-reminders-modal"), %(id="setup-reminders-modal"))
    expect(body.scan(%r{action="[^"]*send_payment_reminders"}).size).to eq(1) # only the modal's form posts
    expect(body).not_to match(/<form[^>]*send_payment_reminders[^>]*>(?:(?!<\/form>).)*<form/m)
  end

  it "sends the edited copy, filled in per person, only to the people still ticked" do
    expect {
      post manage_send_payment_reminders_money_show_payout_path(show), params: {
        person_ids: [ ollie.id.to_s, nolan.id.to_s ],
        reminder_subject: "{{amount}} is waiting for you, {{recipient_name}}",
        reminder_body: "<p>Hi {{recipient_name}}, set up here: {{setup_link}}</p>"
      }
    }.to change(Message, :count).by(1)

    expect(response).to redirect_to(manage_money_show_payout_path(show))
    expect(flash[:notice]).to eq("Sent 1 payment-setup reminder.")
    message = Message.order(:id).last
    expect(message.subject).to eq("$120.00 is waiting for you, Ollie")
    expect(message.body.to_s).to include("Hi Ollie, set up here:", "/my/payments")
    expect(message.body.to_s).not_to include("{{")
  end

  it "sends nothing when nobody is ticked or the draft is empty" do
    expect {
      post manage_send_payment_reminders_money_show_payout_path(show), params: { reminder_subject: "Hi", reminder_body: "<p>Hi</p>" }
    }.not_to change(Message, :count)
    expect(flash[:alert]).to eq("Nobody was ticked, so nothing was sent.")

    expect {
      post manage_send_payment_reminders_money_show_payout_path(show), params: { person_ids: [ ollie.id.to_s ], reminder_subject: "", reminder_body: "<p>Hi</p>" }
    }.not_to change(Message, :count)
    expect(flash[:alert]).to eq("The reminder needs a subject and a message.")
  end
end
