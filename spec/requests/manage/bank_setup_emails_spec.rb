# frozen_string_literal: true

require "rails_helper"

# Bank setup links go to the payee's own email and are never shown to
# managers (Tim, 2026-10-12): a manager who could open one could connect their
# own bank to someone else's payouts.
RSpec.describe "Emailing a bank setup link", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:contractor) { org.contractors.create!(name: "Sound Co") }
  let!(:person) { create(:person, name: "Sam Sound", email: "sam@example.com").tap { |p| org.people << p } }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    contractor.update!(person: person)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    ActionMailer::Base.deliveries.clear
  end

  it "emails the payee their own link, records it, and the page offers Resend" do
    perform_enqueued_jobs do
      post manage_bank_setup_emails_path, params: { payee_type: "Person", payee_id: person.id },
                                          headers: { "HTTP_REFERER" => manage_contractor_path(contractor) }
    end
    expect(response).to redirect_to(manage_contractor_path(contractor))
    expect(flash[:notice]).to eq("Bank setup link emailed to Sam Sound.")

    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq([ "sam@example.com" ])
    expect(mail.subject).to eq("Stars & Garters wants to pay you through CocoScout")
    token = mail.html_part.decoded[%r{/pay/setup/([^"&]+)}, 1]
    expect(PayeeOnboardingToken.resolve(CGI.unescape(token))).to eq(person)
    expect(BankSetupEmail.sole).to have_attributes(organization_id: org.id, payee: person, email: "sam@example.com", sent_by_id: owner.id)

    get manage_contractor_path(contractor)
    expect(response.body).to include("Resend setup link", "Sent #{Date.current.strftime('%b %-d')} to their email")
    expect(response.body).not_to include("/pay/setup/")
  end

  it "never sends for another organization's people" do
    stranger = create(:person, email: "stranger@example.com")

    post manage_bank_setup_emails_path, params: { payee_type: "Person", payee_id: stranger.id }
    expect(response).to have_http_status(:not_found)
    expect(BankSetupEmail.count).to eq(0)
  end

  it "stops honoring links made before they were emailed only" do
    old = Rails.application.message_verifier("payee_onboarding")
                .generate({ "t" => "Person", "id" => person.id }, expires_in: 30.days, purpose: "payee_onboarding")
    expect(PayeeOnboardingToken.resolve(old)).to be_nil
  end
end
