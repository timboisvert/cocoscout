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

  it "comes from CocoScout to the organization, with Stripe's number, and shows a usage bill as CocoScout's own count, naming the people" do
    StaffActivation.create!(organization: org, person: create(:person, name: "Phoebe Staff"), billing_month: Date.new(2026, 9, 1))
    PerformerActivation.create!(organization: org, person: create(:person, name: "Marina Act"), billing_month: Date.new(2026, 9, 1))
    PerformerActivation.create!(organization: org, person: create(:person, name: "Colin Act"), billing_month: Date.new(2026, 9, 1))

    document = described_class.document(bill)

    expect(document.number).to eq("ABCD-0007")
    expect(document.seller.name).to eq("CocoScout (Coco Runs Everything LLC)")
    expect(document.seller.lines).to eq([ "1714 S. Desplaines St.", "Chicago, IL 60616" ])
    expect(document.bill_to.name).to eq("Stars & Garters")
    expect(document.reference).to eq([ [ "Bill", "September 2026 usage" ] ])
    # Tim, 2026-11-01: the theater sees the count CocoScout bills by, never
    # Stripe's meter lines or the correction that brought them to that count.
    expect(document.items.map { |item| [ item.description, item.amount_cents ] })
      .to eq([ [ "1 active staff member × $5.00", 500 ], [ "2 active performers × $3.00", 600 ] ])
    expect(document.items.map(&:detail)).to eq([ "Staff with a paid shift in September 2026, counted once each.",
                                                "Performers paid for a show in September 2026, counted once each." ])
    expect(document.items.sum(&:amount_cents)).to eq(document.total_cents)
    expect(document.sections).to eq([
      [ "Staff with a paid shift in September 2026", [ "Phoebe Staff" ] ],
      [ "Performers paid for a show in September 2026", [ "Colin Act", "Marina Act" ] ]
    ])
    expect(document.status_line).to eq("Paid October 3, 2026")
    text = pdf_text(InvoicePdf.new(document).render)
    expect(text).to include("PAID", "ABCD-0007", "Marina Act", "2 active performers")
    expect(text).not_to include("Correction", "Staff usage", "Performer usage")
  end

  it "says by how much a usage bill issued before its count was checked differs, so the lines still add up" do
    StaffActivation.create!(organization: org, person: create(:person, name: "Phoebe Staff"), billing_month: Date.new(2026, 9, 1))
    old = bill(amount_due_cents: 1_700, amount_paid_cents: 1_700,
               lines: [ { "description" => "2 × active staff member", "amount_cents" => 1_000 },
                        { "description" => "2 × active performer", "amount_cents" => 700 } ])

    document = described_class.document(old)
    expect(document.items.map { |item| [ item.description, item.amount_cents ] })
      .to eq([ [ "1 active staff member × $5.00", 500 ], [ "Billed before this count was checked", 1_200 ] ])
    expect(document.items.sum(&:amount_cents)).to eq(1_700)
  end

  it "tells the billing contacts the count, not Stripe's lines" do
    StaffActivation.create!(organization: org, person: create(:person, name: "Phoebe Staff"), billing_month: Date.new(2026, 9, 1))
    PerformerActivation.create!(organization: org, person: create(:person, name: "Marina Act"), billing_month: Date.new(2026, 9, 1))
    PerformerActivation.create!(organization: org, person: create(:person, name: "Colin Act"), billing_month: Date.new(2026, 9, 1))
    ActionMailer::Base.deliveries.clear

    BillingInvoiceEmailJob.perform_now(bill(status: "open", amount_paid_cents: 0, paid_at: nil).id, "bill")

    body = ActionMailer::Base.deliveries.last.html_part.body.decoded
    expect(body).to include("1 active staff member × $5.00: $5.00", "2 active performers × $3.00: $6.00")
    expect(body).not_to include("Correction", "Staff usage")
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
