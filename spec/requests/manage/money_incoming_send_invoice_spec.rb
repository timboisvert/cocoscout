# frozen_string_literal: true

require "rails_helper"

# "Send invoice" on the Collect page (Tim, 2026-10-05): a manager presses it,
# the payer gets the invoice with its PDF; pressing again sends a reminder.
# Nothing sends an invoice without a manager.
RSpec.describe "Sending a contract invoice", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner) }
  let!(:owner_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let(:contract) { create(:contract, :active, organization: org, contractor_name: "Gigi Noble Wolf", contractor_email: "gigi@example.com") }
  let(:payment) do
    create(:contract_payment, contract: contract, direction: "incoming", amount: 350, amount_tbd: false,
                              due_date: Date.new(2026, 10, 10), description: "Rent", settlement_method: "direct")
  end

  before do
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    ActionMailer::Base.deliveries.clear
  end

  it "shows the invoice number on the Collect page and sends the invoice with its PDF, then a reminder" do
    get manage_money_incoming_payment_path(payment)
    expect(response.body).to include("Invoice SG-0001", "Send invoice")

    perform_enqueued_jobs do
      post manage_send_invoice_money_incoming_payment_path(payment), params: { custom_message: "Thanks so much!" }
    end
    expect(response).to redirect_to(manage_money_incoming_payment_path(payment))
    expect(flash[:notice]).to eq("Invoice SG-0001 sent to gigi@example.com.")

    mail = ActionMailer::Base.deliveries.last
    expect(mail.subject).to eq("Invoice SG-0001 from Stars & Garters: $350.00 due October 10, 2026")
    expect(mail.html_part.body.decoded).to include("Thanks so much!", "/pay/contract/")
    expect(mail.attachments.reject(&:inline?).map(&:filename)).to eq([ "Invoice SG-0001.pdf" ])

    perform_enqueued_jobs { post manage_send_invoice_money_incoming_payment_path(payment) }
    expect(ActionMailer::Base.deliveries.last.subject).to start_with("Reminder: invoice SG-0001")
    expect(payment.reload.contract_invoice.sent_count).to eq(2)
  end

  it "says so when the payer has no email, and sends nothing" do
    contract.update_columns(contractor_email: nil)
    perform_enqueued_jobs { post manage_send_invoice_money_incoming_payment_path(payment) }

    expect(flash[:alert]).to include("No email on file")
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "can't reach another organization's payment" do
    other = create(:contract_payment, contract: create(:contract, :active), direction: "incoming", amount: 10, amount_tbd: false)

    post manage_send_invoice_money_incoming_payment_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it "never queues an invoice email when payments are created or come due" do
    expect { payment; travel_to(Date.new(2026, 10, 11)) { payment.touch } }.not_to have_enqueued_mail(ContractInvoiceMailer)
  end
end
