# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Superadmin Finances - Org Payouts", type: :request do
  let(:superadmin_user) { create(:user, email_address: "boisvert@gmail.com", password: "Password123!") }
  let(:regular_user) { create(:user, password: "Password123!") }

  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:course_offering) { create(:course_offering, production: production) }

  def sign_in_as_superadmin
    post handle_signin_path, params: { email_address: superadmin_user.email_address, password: "Password123!" }
  end

  def sign_in_as_regular
    post handle_signin_path, params: { email_address: regular_user.email_address, password: "Password123!" }
  end

  describe "the Finances pages" do
    before { sign_in_as_superadmin }

    it "says in words when CocoScout is short, never as a minus sign" do
      PlatformReconciliation.create!(checked_at: Time.current, checked_on: Date.current, stripe_balance_cents: 100_000,
                                     held_for_orgs_cents: 130_985, cocoscout_cents: -30_985, imported_net_cents: 100_000, difference_cents: 0)
      CocoScoutLedgerEntry.create!(entry_type: "funding_cost", amount_cents: -50_000, occurred_at: Time.current)
      get finances_path
      expect(response.body).to include("CocoScout is short", "Leave the next $500.00 we collect in Stripe", "$1,309.85 of it held for organizations",
                                       "Spent more than earned", "$500.00 spent against $0.00 earned")
      expect(response.body).not_to include("-$309.85", "-$500.00", "theater")
    end

    it "says what's ours to withdraw, what's owed to us, and where each stream's profit comes from" do
      PlatformReconciliation.create!(checked_at: Time.current, checked_on: Date.current, stripe_balance_cents: 500_000, held_for_orgs_cents: 480_000,
                                     cocoscout_cents: 20_000, imported_net_cents: 500_000, difference_cents: 0,
                                     details: { "stripe_available_cents" => 12_000, "stripe_pending_cents" => 488_000 })
      CocoScoutLedgerEntry.create!(entry_type: "ticket_fee", amount_cents: 15_000, occurred_at: Time.current, organization: organization)
      CocoScoutLedgerEntry.create!(entry_type: "ticket_processing", amount_cents: 9_000, occurred_at: Time.current, organization: organization)
      CocoScoutLedgerEntry.create!(entry_type: "processing_cost", amount_cents: -8_000, occurred_at: Time.current, source_type: "TicketOrder", source_id: 1)
      CocoScoutLedgerEntry.create!(entry_type: "stripe_fee", amount_cents: -6_000, occurred_at: Time.current,
                                   description: "Connect (2026-10-01 - 2026-10-31): Active Accounts")
      CocoScoutLedgerEntry.create!(entry_type: "payout_to_bank", amount_cents: -5_000, occurred_at: 2.days.ago)
      late = BillingInvoice.create!(organization: organization, stripe_invoice_id: "in_late", kind: "usage", status: "open", amount_due_cents: 4_200,
                                    amount_remaining_cents: 4_200, finalized_at: 10.days.ago, created_at: 10.days.ago, period_start: 40.days.ago)
      BillingInvoice.create!(organization: organization, stripe_invoice_id: "in_paid", kind: "pro", status: "paid", amount_due_cents: 2_000,
                             amount_paid_cents: 2_000, finalized_at: 1.hour.ago, paid_at: 1.hour.ago)

      get finances_path
      body = response.body
      # Profit $120 (the paid Pro bill counts), $50 already at the bank: $70 ours; Stripe has $120 available.
      expect(body).to include("Ready to withdraw", "Profit since we started", "$120.00", "already gone to our bank", "Ours, still in Stripe")
      expect(body).to include("$70.00 ready to withdraw, $0.00 still arriving", "Pro bills paid")
      # The late bill is earned, just not collected: $162 profit, $42 of it still to collect.
      expect(body).to include("$162.00", "Less bills sent, not collected yet", "Since we started")
      expect(body).to include("Owed to us", "Late", late.title, "$42.00", "Bills not yet paid")
      expect(body).to include("Tickets", "50¢ ticket fees (300 tickets)", "$150.00", "card processing on tickets", "less $80.00", "We kept", "$160.00")
      expect(body).to include("Running CocoScout", "Stripe: Connect: Active Accounts", "Cost us", "$60.00")
      expect(body).to include("Month by month", "Bills sent in this period", "Pro plan", "Paid")
    end

    it "shows CocoScout's own money, apart from the organizations'" do
      listing = create(:ticket_listing, organization: organization)
      tier = listing.ticket_tiers.create!(name: "General", price_cents: 2_000, quantity: 60)
      order = TicketCheckout.start!(listing: listing, quantities: { tier.id.to_s => "2" })
      order.update!(buyer_name: "Avery", buyer_email: "avery@example.com")
      TicketOrderSettlement.settle!(order, payment_intent_id: "pi_1", charge_id: "ch_1")

      get finances_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tickets", "50¢ ticket fees (2 tickets)", "$1.00", "Who paid us", organization.name)

      get finances_path(period: "this_month", format: :csv)
      expect(response.media_type).to eq("text/csv")
      expect(response.body).to include("Ticket fees (50¢ a ticket)", organization.name, "1.00")
    end

    it "says when an organization paid a month twice, and keeps it out of what's ours" do
      month = { period_start: Time.zone.local(2026, 10, 1), period_end: Time.zone.local(2026, 11, 1), paid_at: Time.current }
      BillingInvoice.create!(organization: organization, stripe_invoice_id: "in_a", number: "SG-0003", kind: "usage", status: "paid",
                             amount_due_cents: 15_900, amount_paid_cents: 15_900, **month)
      BillingInvoice.create!(organization: organization, stripe_invoice_id: "in_b", number: "SG-0004", kind: "usage", status: "paid",
                             amount_due_cents: 15_900, amount_paid_cents: 15_900, **month)
      get finances_path
      expect(response.body).to include("paid October 2026 usage twice", "Bill SG-0004", "usage:overbilled[#{organization.id},refund]",
                                       "Plus bills paid twice, owed back", "$159.00 owed back")
    end

    it "lists each organization's money, and one organization's in full" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10_000, status: "confirmed", stripe_payment_intent_id: "pi_c", cocoscout_fee_cents: 1_000)
      batch = organization.payout_batches.create!(kind: "payout", status: "funding", trigger: "manual", total_cents: 200_000, funding_status: "processing")
      get finances_organizations_path
      expect(response.body).to include(organization.name, "Moving now")

      get finances_org_detail_path(org_id: organization.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("We hold for them", "Payout run ##{batch.id}: bank debit on its way in", "$2,000.00", "Every movement of their balance",
                                       "Course payments recorded by hand")
      get finances_org_courses_path(org_id: organization.id)
      expect(response.body).to include("Course Breakdown")
    end

    it "shows plans, comps and bills" do
      organization.update!(comped_indefinitely: true, comped_usage: false, stripe_customer_id: "cus_1")
      BillingInvoice.create!(organization: organization, stripe_invoice_id: "in_1", kind: "usage", status: "open", amount_due_cents: 3_500,
                             amount_remaining_cents: 3_500, failed_at: Time.current, period_start: 1.month.ago)
      get finances_subscriptions_path
      expect(response.body).to include("Plan comped · usage billed", "Usage, $35.00: payment failed", "Bills that failed")
    end

    it "shows the Stripe check, and lets a line be explained" do
      line = StripeBalanceTransaction.create!(stripe_id: "txn_1", txn_type: "adjustment", reporting_category: "other_adjustment", amount_cents: 500,
                                              net_cents: 500, occurred_at: Time.current)
      allow(Stripe::Balance).to receive(:retrieve).and_return(Stripe::Balance.construct_from(available: [ { amount: 500, currency: "usd" } ], pending: []))
      PlatformReconciliationCheck.run!

      get finances_stripe_check_path
      expect(response.body).to include("Stripe lines that need a look (1)", "Not recognized", "Record $5.00 as the opening difference")

      post finances_explain_line_path(line), params: { note: "Stripe test credit" }
      expect(line.reload.match_status).to eq("explained")
      expect(PlatformReconciliation.latest).to be_clean
    end

    it "names the record a mismatched line belongs to" do
      registration = create(:course_registration, course_offering: course_offering, amount_cents: 7_000, status: "confirmed", stripe_payment_intent_id: "pi_m")
      StripeBalanceTransaction.create!(stripe_id: "txn_m", txn_type: "charge", reporting_category: "charge", amount_cents: 7_500, net_cents: 7_500,
                                       occurred_at: Time.current, category: "course_registration", match_status: "mismatch",
                                       matched: registration, expected_cents: 7_000)
      get finances_stripe_check_path
      expect(response.body).to include("Course registration ##{registration.id}: amount disagrees (ours $70.00)")
    end

    it "redirects non-superadmins" do
      sign_in_as_regular
      get finances_path
      expect(response).to redirect_to(my_dashboard_path)
    end
  end

  describe "GET /superadmin/finances/courses/:course_offering_id" do
    before { sign_in_as_superadmin }

    it "shows course detail page with revenue summary" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      get finances_course_detail_path(course_offering_id: course_offering.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(course_offering.title)
      expect(response.body).to include("Revenue Summary")
      expect(response.body).to include("Record Payment")
    end

    it "shows fully paid message when balance is zero" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      owed = OrgPayout.owed_cents_for_course(course_offering)
      create(:org_payout, organization: organization, course_offering: course_offering, amount_cents: owed)
      get finances_course_detail_path(course_offering_id: course_offering.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fully Paid")
    end
  end

  describe "POST /superadmin/finances/courses/:course_offering_id/pay" do
    before { sign_in_as_superadmin }

    it "creates a full_course payment" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, cocoscout_fee_cents: 1000, status: "confirmed")

      expect {
        post finances_record_payment_path(course_offering_id: course_offering.id), params: {
          payout_type: "full_course",
          payment_method: "check",
          notes: "Full course payment"
        }
      }.to change(OrgPayout, :count).by(1)

      payout = OrgPayout.last
      expect(payout.amount_cents).to eq(9000) # 10000 gross - 1000 stored CocoScout fee
      expect(payout.payout_type).to eq("full_course")
      expect(payout.payment_method).to eq("check")
      expect(payout.status).to eq("paid")
      expect(response).to redirect_to(finances_course_detail_path(course_offering_id: course_offering.id))
    end

    it "creates a custom payment" do
      expect {
        post finances_record_payment_path(course_offering_id: course_offering.id), params: {
          payout_type: "custom",
          amount: "50.00",
          payment_method: "cash",
          notes: "Partial"
        }
      }.to change(OrgPayout, :count).by(1)

      expect(OrgPayout.last.amount_cents).to eq(5000)
    end

    it "creates a per_session payment" do
      location = create(:location, organization: organization)
      show1 = create(:show, production: production, course_offering: course_offering, location: location, date_and_time: 1.day.from_now)
      show2 = create(:show, production: production, course_offering: course_offering, location: location, date_and_time: 2.days.from_now)
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, cocoscout_fee_cents: 1000, status: "confirmed")

      expect {
        post finances_record_payment_path(course_offering_id: course_offering.id), params: {
          payout_type: "per_session",
          session_ids: [ show1.id ],
          payment_method: "cash"
        }
      }.to change(OrgPayout, :count).by(1)

      payout = OrgPayout.last
      expect(payout.payout_type).to eq("per_session")
      expect(payout.covers_sessions).to eq([ show1.id ])
      # 9000 owed total / 2 sessions * 1 session = 4500
      expect(payout.amount_cents).to eq(4500)
    end
  end

  describe "DELETE /superadmin/finances/payments/:id" do
    before { sign_in_as_superadmin }

    it "deletes a payment and redirects to course detail" do
      payout = create(:org_payout, organization: organization, course_offering: course_offering)

      expect {
        delete finances_delete_payment_path(id: payout.id)
      }.to change(OrgPayout, :count).by(-1)

      expect(response).to redirect_to(finances_course_detail_path(course_offering_id: course_offering.id))
    end

    it "redirects to org detail if no course_offering" do
      payout = create(:org_payout, organization: organization, course_offering: nil)

      delete finances_delete_payment_path(id: payout.id)
      expect(response).to redirect_to(finances_org_courses_path(org_id: organization.id))
    end
  end

  describe "POST /superadmin/finances/payments/:id/mark_paid" do
    before { sign_in_as_superadmin }

    it "marks a pending payment as paid" do
      payout = create(:org_payout, :pending, organization: organization, course_offering: course_offering)

      post finances_mark_payment_paid_path(id: payout.id)
      payout.reload
      expect(payout.status).to eq("paid")
      expect(payout.paid_at).to be_present
      expect(payout.paid_by_user).to eq(superadmin_user)
    end
  end
end
