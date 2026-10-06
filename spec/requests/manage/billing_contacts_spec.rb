# frozen_string_literal: true

require "rails_helper"

# Billing contacts (Tim, 2026-10-06): who gets CocoScout's bills, receipts
# and monthly statements. Ticked managers plus other addresses; nobody chosen
# means the owner, as before.
RSpec.describe "Billing contacts", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:owner) { create(:user, email_address: "owner@sg.example", password: password) }
  let!(:owner_person) { create(:person, user: owner, name: "Tim Owner") }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner, stripe_customer_id: "cus_sg") }
  let(:manager) { create(:user, email_address: "andie@sg.example") }
  let!(:manager_person) { create(:person, user: manager, name: "Andie Manager") }

  before do
    create(:organization_role, :manager, user: owner, organization: org)
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  def bill
    BillingInvoice.create!(organization: org, stripe_invoice_id: "in_contacts", number: "SG-0009", kind: "pro", status: "paid",
                           amount_due_cents: 2_000, amount_paid_cents: 2_000, paid_at: Time.current,
                           period_start: 1.month.ago, period_end: Time.current, finalized_at: Time.current,
                           lines: [ { "description" => "Pro plan, monthly", "quantity" => 1, "amount_cents" => 2_000 } ])
  end

  it "shows the owner ticked until someone chooses, and saves managers and other addresses" do
    get section_manage_organization_path(org, section: "billing")
    expect(response.body).to include("Who gets the bills")
    expect(response.body).to match(/id="billing_contact_user_#{owner.id}"[^>]*checked/)
    expect(response.body).not_to match(/id="billing_contact_user_#{manager.id}"[^>]*checked/)

    allow(Stripe::Customer).to receive(:update)
    perform_enqueued_jobs do
      patch manage_billing_contacts_path, params: { billing_contact_user_ids: [ manager.id, 999_999 ], billing_contact_emails: "Accounting@sg.example\n" }
    end
    expect(response).to redirect_to(section_manage_organization_path(org, section: "billing"))
    expect(org.reload.billing_contact_user_ids).to eq([ manager.id ])
    expect(org.billing_contact_emails).to eq([ "accounting@sg.example" ])
    expect(org.billing_contacts.map(&:email)).to eq([ "andie@sg.example", "accounting@sg.example" ])
    expect(Stripe::Customer).to have_received(:update).with("cus_sg", { email: "andie@sg.example", name: "Stars & Garters" })

    patch manage_billing_contacts_path, params: { billing_contact_user_ids: [], billing_contact_emails: "not-an-email" }
    expect(flash[:alert]).to eq("not-an-email isn't an email address.")
    expect(org.reload.billing_contact_emails).to eq([ "accounting@sg.example" ])
  end

  it "sends the receipt and the statement to every contact, by first name" do
    org.update!(billing_contact_user_ids: [ owner.id, manager.id ], billing_contact_emails: [ "accounting@sg.example" ])
    ActionMailer::Base.deliveries.clear

    BillingInvoiceEmailJob.perform_now(bill.id, "receipt")
    receipts = ActionMailer::Base.deliveries
    expect(receipts.map(&:to).flatten).to contain_exactly("owner@sg.example", "andie@sg.example", "accounting@sg.example")
    expect(receipts.find { |m| m.to == [ "andie@sg.example" ] }.html_part.body.decoded).to include("Hi Andie,")
    expect(receipts.find { |m| m.to == [ "accounting@sg.example" ] }.html_part.body.decoded).to include("Hi there,")

    ActionMailer::Base.deliveries.clear
    OrgStatementJob.perform_now(org.id, "2026-09-01")
    expect(ActionMailer::Base.deliveries.map(&:to).flatten).to contain_exactly("owner@sg.example", "andie@sg.example", "accounting@sg.example")
  end

  it "falls back to the owner, and drops a manager who left" do
    expect(org.billing_contacts).to eq([ Organization::BillingContact.new("owner@sg.example", "Tim") ])

    org.update!(billing_contact_user_ids: [ manager.id ])
    org.organization_roles.where(user: manager).destroy_all
    expect(org.billing_contacts.map(&:email)).to eq([ "owner@sg.example" ])
  end
end
