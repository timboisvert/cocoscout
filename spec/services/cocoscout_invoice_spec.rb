# frozen_string_literal: true

require "rails_helper"

# CocoScout's own invoices for Pro and usage (Tim, 2026-10-05: "if we're
# already building our own invoices, why not for Pro and usage?"). Stripe
# still charges; the invoice carries Stripe's number.
RSpec.describe CocoScoutInvoice do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro, name: "Stars & Garters") }

  def bill(**attrs)
    BillingInvoice.create!({ organization: org, stripe_invoice_id: "in_#{SecureRandom.hex(4)}", number: "ABCD-0007", kind: "usage",
                             status: "paid", amount_due_cents: 1_100, amount_paid_cents: 1_100,
                             period_start: Time.zone.local(2026, 8, 30), period_end: Time.zone.local(2026, 9, 30),
                             finalized_at: Time.zone.local(2026, 9, 30, 12), paid_at: Time.zone.local(2026, 10, 3),
                             lines: [ { "description" => "Staff usage", "quantity" => 1, "amount_cents" => 500 },
                                      { "description" => "Performer usage", "quantity" => 1, "amount_cents" => 300 },
                                      { "description" => "#{UsageInvoiceCorrection::PREFIX} 1 staff and 2 performers paid through CocoScout in September 2026", "amount_cents" => 300 } ] }
                           .merge(attrs))
  end

  def pdf_text(bytes)
    bytes.scan(/<([0-9a-fA-F]+)>/).flatten.map { |hex| [ hex ].pack("H*") }.join
  end

  it "comes from CocoScout to the organization, with Stripe's number, and names the people a usage bill counted" do
    StaffActivation.create!(organization: org, person: create(:person, name: "Phoebe Staff"), billing_month: Date.new(2026, 9, 1))
    PerformerActivation.create!(organization: org, person: create(:person, name: "Marina Act"), billing_month: Date.new(2026, 9, 1))
    PerformerActivation.create!(organization: org, person: create(:person, name: "Colin Act"), billing_month: Date.new(2026, 9, 1))

    document = described_class.document(bill)

    expect(document.number).to eq("ABCD-0007")
    expect(document.seller.name).to eq("CocoScout (Coco Runs Everything LLC)")
    expect(document.seller.lines).to eq([ "1714 S. Desplaines St.", "Chicago, IL 60616" ])
    expect(document.bill_to.name).to eq("Stars & Garters")
    expect(document.reference).to eq([ [ "Bill", "September 2026 usage" ] ])
    expect(document.items.last.detail).to include("CocoScout's records")
    expect(document.sections).to eq([
      [ "Staff with a paid shift in September 2026 (1 × $5.00)", [ "Phoebe Staff" ] ],
      [ "Performers paid for a show in September 2026 (2 × $3.00)", [ "Colin Act", "Marina Act" ] ]
    ])
    expect(document.status_line).to eq("Paid October 3, 2026")
    expect(pdf_text(InvoicePdf.new(document).render)).to include("PAID", "ABCD-0007", "Marina Act")
  end

  it "shows a Pro bill's period, and an account credit so the lines add up to what was charged" do
    pro = bill(kind: "pro", status: "open", amount_due_cents: 1_500, amount_paid_cents: 0, paid_at: nil,
               period_start: Time.zone.local(2026, 10, 5), period_end: Time.zone.local(2026, 11, 5),
               lines: [ { "description" => "1 × Pro (at $20.00 / month)", "amount_cents" => 2_000 } ])

    document = described_class.document(pro)
    expect(document.reference).to include([ "Period", "Oct 5, 2026 to Nov 5, 2026" ])
    expect(document.items.map { |item| [ item.description, item.amount_cents ] })
      .to eq([ [ "1 × Pro (at $20.00 / month)", 2_000 ], [ "Credit from your CocoScout account", -500 ] ])
    expect(document.total_cents).to eq(1_500)
    expect(document.status).to eq(:due)
  end

  describe "downloading it", type: :request do
    let(:password) { "Password123!" }
    let(:owner) { create(:user, password: password) }

    before do
      org.update!(owner: owner)
      create(:organization_role, :manager, user: owner, organization: org)
      post handle_signin_path, params: { email_address: owner.email_address, password: password }
    end

    it "gives the organization its own bill's invoice as a PDF, and never another organization's" do
      get manage_billing_invoice_path(bill)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")

      theirs = BillingInvoice.create!(organization: create(:organization), stripe_invoice_id: "in_theirs", kind: "pro", status: "paid")
      get manage_billing_invoice_path(theirs)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "attaches the invoice to the bill and receipt emails" do
    paid = bill
    ActionMailer::Base.deliveries.clear

    BillingInvoiceEmailJob.perform_now(paid.id, "receipt")

    mail = ActionMailer::Base.deliveries.last
    expect(mail.attachments.reject(&:inline?).map(&:filename)).to eq([ described_class.filename(paid) ])
    expect(mail.html_part.body.decoded).to include("/manage/billing/invoices/#{paid.id}")
  end
end
