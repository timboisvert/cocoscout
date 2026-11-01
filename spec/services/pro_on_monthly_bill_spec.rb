# frozen_string_literal: true

require "rails_helper"

# Pro paid on the one monthly bill (Tim, 2026-11-01): each month's bill
# carries the plan for that month beside its usage, so an organization gets
# one bill, not one for Pro and another for usage.
RSpec.describe "Pro on the monthly bill", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:owner_person) { create(:person, user: owner) }
  let(:org) { create(:organization, name: "Stars & Garters", owner: owner, stripe_customer_id: "cus_sg", staffing_subscription_id: "sub_usage") }
  let(:november) { Date.new(2026, 11, 1) }

  before { create(:organization_role, :manager, user: owner, organization: org) }

  def sign_in
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
    get manage_path
  end

  it "makes the organization Pro from the day it starts, at $29 a month, by the day for a part month" do
    org.update!(pro_monthly_from: Time.zone.local(2026, 11, 1, 15, 30))
    expect([ org.pro_on_monthly_bill?(Time.zone.local(2026, 11, 2)), org.on_paid_plan?, org.bills_usage? ]).to eq([ true, true, true ])
    expect(UsageRules.pro_cents(org, november)).to eq(2_900)
    expect(UsageRules.pro_cents(org, Date.new(2026, 10, 1))).to eq(0)

    org.update!(pro_monthly_from: Time.zone.local(2026, 11, 16, 9))
    expect(UsageRules.pro_cents(org, november)).to eq(1_450)
    # Canceled: Pro through the end of the month it was canceled in, then nothing.
    org.update!(pro_monthly_from: Time.zone.local(2026, 9, 1), pro_monthly_until: Time.zone.local(2026, 11, 30).end_of_day)
    expect([ UsageRules.pro_cents(org, november), UsageRules.pro_cents(org, Date.new(2026, 12, 1)) ]).to eq([ 2_900, 0 ])
    # Comped through November 10: the rest of the month.
    org.update!(pro_monthly_until: nil, comped_until: Time.zone.local(2026, 11, 10).end_of_day)
    expect(UsageRules.pro_cents(org, november)).to eq(1_933)
  end

  it "puts Pro first on the month's bill, and the books count it as Pro, the rest as usage" do
    org.update!(pro_monthly_from: Time.zone.local(2026, 11, 1, 15, 30))
    performer = create(:person)
    PerformerActivation.record!(organization: org, person: performer, month: november)
    record = BillingInvoice.create!(organization: org, stripe_invoice_id: "in_nov", kind: "usage", status: "draft", amount_due_cents: 300,
                                    period_start: Time.zone.local(2026, 11, 1), period_end: Time.zone.local(2026, 12, 1),
                                    lines: [ { "description" => "usage", "amount_cents" => 300 } ])
    expect(Stripe::InvoiceItem).to receive(:create)
      .with(hash_including(invoice: "in_nov", amount: 2_900, description: "Pro plan, November 2026"), hash_including(idempotency_key: "pro-plan-in_nov-2900"))
    UsageInvoiceCorrection.apply!(record)

    record.update!(status: "paid", amount_due_cents: 3_200, amount_paid_cents: 3_200, paid_at: Time.current,
                   lines: [ { "description" => "usage", "amount_cents" => 300 }, { "description" => "Pro plan, November 2026", "amount_cents" => 2_900 } ])
    expect(record.title).to eq("November 2026: Pro and usage")
    expect(CocoScoutInvoice.document(record).items.map { |line| [ line.description, line.amount_cents ] })
      .to eq([ [ "Pro plan, November 2026", 2_900 ], [ "1 other person paid × $3.00", 300 ] ])
    entries = CocoScoutLedgerEntry.where(source: record).pluck(:entry_type, :amount_cents).to_h
    expect(entries).to eq("subscription" => 2_900, "usage" => 300)
  end

  it "shows it on the Billing tab, and cancels it to the end of the month" do
    travel_to Time.zone.local(2026, 11, 12, 10) do
      org.update!(pro_monthly_from: Time.zone.local(2026, 11, 1, 15, 30))
      sign_in
      get section_manage_organization_path(org, section: "billing")
      expect(response.body).to include("/month, on your one monthly bill with your usage", "Next bill December 1", "Cancel Pro",
                                       "This month&#39;s bill", "Pro plan $29.00 + usage $0.00, on one bill")
      post manage_billing_cancel_pro_path
      expect(flash[:notice]).to include("stays on through November 30")
      expect(org.reload.pro_monthly_until.to_date).to eq(Date.new(2026, 11, 30))
      expect(org.on_paid_plan?).to be(true)
    end
  end

  it "starts monthly Pro from checkout by saving the card or bank, never a second subscription" do
    org.update!(staffing_subscription_id: nil)
    sign_in
    expect(Stripe::Checkout::Session).to receive(:create).with(hash_including(mode: "setup", customer: "cus_sg", metadata: hash_including(kind: "pro_monthly")))
                                                         .and_return(double(url: "https://checkout.stripe.com/setup"))
    post manage_billing_checkout_path(interval: "month")
    expect(response).to redirect_to("https://checkout.stripe.com/setup")

    session = Stripe::Checkout::Session.construct_from(id: "cs_1", mode: "setup", setup_intent: "seti_1", metadata: { organization_id: org.id.to_s, kind: "pro_monthly" })
    allow(Stripe::Checkout::Session).to receive(:retrieve).with("cs_1").and_return(session)
    allow(Stripe::SetupIntent).to receive(:retrieve).with("seti_1").and_return(Stripe::SetupIntent.construct_from(id: "seti_1", payment_method: "pm_bank"))
    expect(Stripe::Customer).to receive(:update).with("cus_sg", invoice_settings: { default_payment_method: "pm_bank" })
    expect(StaffMeterService).to receive(:ensure_staffing_subscription!).with(org)
    get manage_billing_success_path(session_id: "cs_1")
    expect(org.reload.pro_on_monthly_bill?).to be(true)
    expect(flash[:notice]).to include("You're on CocoScout Pro")
  end
end
