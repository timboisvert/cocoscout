# frozen_string_literal: true

require "rails_helper"

# The manager's money pages in Ticketing: orders and refunds, the CocoScout
# balance and withdrawals, taxes collected, and canceling a show.
RSpec.describe "Manage ticketing money", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let(:superadmin) { create(:user, email_address: "boisvert@gmail.com", password: password) }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: superadmin, stripe_account_id: "acct_sg", payouts_enabled: true) }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }

  before do
    create(:organization_role, :manager, user: superadmin, organization: org)
    post handle_signin_path, params: { email_address: superadmin.email_address, password: password }
    get manage_path
    allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1"))
  end

  def sold(count, name: "Dana Scully")
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: name, buyer_email: "#{name.parameterize}@example.com")
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{order.id}")
    order.reload
  end

  describe "orders" do
    it "finds orders by name or code, and shows one" do
      dana = sold(2)
      sold(1, name: "Fox Mulder")

      get manage_ticket_orders_path, params: { q: "scul" }
      expect(response.body).to include("Dana Scully")
      expect(response.body).not_to include("Fox Mulder")
      get manage_ticket_orders_path, params: { q: dana.code.downcase }
      expect(response.body).to include("Dana Scully")

      get manage_ticket_order_path(dana.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("$42.53", "You keep", "Review refund", "Keep the fees")
      expect(response.body).not_to include(dana.token.first(12) + "/refund")
    end

    it "reviews a refund, then issues it" do
      order = sold(2)
      ids = order.tickets.pluck(:id)

      get manage_ticket_order_refund_path(order.id), params: { ticket_ids: ids, keep_fees: "0" }
      expect(response.body).to include("Refund $42.53 to Dana Scully", "your balance gives up $41.53")

      post manage_ticket_order_refund_path(order.id), params: { ticket_ids: ids, keep_fees: "0", reason: "Asked by email" }
      expect(response).to redirect_to(manage_ticket_order_path(order.id))
      expect(flash[:notice]).to eq("Refunded $42.53 to Dana Scully.")
      expect(order.reload.status).to eq("refunded")
      expect(order.ticket_refunds.sole.reason).to eq("Asked by email")
    end

    it "says so when a refund after the show is more than the balance holds" do
      order = sold(1)
      listing.update!(released_at: 3.days.ago)
      BalanceWithdrawal.create!(organization: org, amount_cents: 2_000, status: "sent")

      get manage_ticket_order_refund_path(order.id), params: { ticket_ids: order.tickets.pluck(:id) }
      expect(response.body).to include("Not enough in your balance")
      expect(response.body).not_to include("Refund $21.42</span>")
    end

    # Round 10: after the show is simply outside the refund policy; a
    # manager can still refund, with Refund anyway and a reason.
    it "refunds after the show only with Refund anyway and a reason" do
      order = sold(1)
      listing.show.update!(date_and_time: 1.hour.ago)
      ids = order.tickets.pluck(:id)

      get manage_ticket_order_path(order.id)
      expect(response.body).to include("Outside the refund policy", "The show has happened", "Review refund")
      get manage_ticket_order_refund_path(order.id), params: { ticket_ids: ids }
      expect(response.body).to include("Refund anyway", 'name="outside_policy"')

      post manage_ticket_order_refund_path(order.id), params: { ticket_ids: ids, keep_fees: "0" }
      expect(flash[:alert]).to eq("This refund is outside the refund policy. Turn on Refund anyway to make it.")
      post manage_ticket_order_refund_path(order.id), params: { ticket_ids: ids, keep_fees: "0", outside_policy: "1" }
      expect(flash[:alert]).to eq("Say why you're refunding outside the policy.")
      expect(order.reload.status).to eq("paid")

      post manage_ticket_order_refund_path(order.id), params: { ticket_ids: ids, keep_fees: "0", outside_policy: "1", reason: "Stuck in traffic" }
      expect(order.reload.status).to eq("refunded")
      expect(order.ticket_refunds.sole).to have_attributes(outside_policy: true, reason: "Stuck in traffic")
    end

    it "won't refund buyers for a show that has started, or one that isn't canceled" do
      sold(1)
      post manage_ticket_listing_cancel_path(listing), params: { subject: "x", body: "y" }
      expect(listing.reload.status).to eq("on_sale")

      listing.show.update!(date_and_time: 1.hour.ago, canceled: true)
      post manage_ticket_listing_cancel_path(listing), params: { subject: "x", body: "y" }
      expect(listing.reload.status).to eq("on_sale")
    end

    it "offers to add the difference from the bank when the balance can't cover a refund, then refunds" do
      org.update!(stripe_customer_id: "cus_sg", funding_payment_method_id: "pm_sg", funding_payment_method_type: "card")
      order = travel_to(5.days.ago) { sold(1) }
      listing.update!(released_at: 3.days.ago)
      BalanceWithdrawal.create!(organization: org, amount_cents: 2_000, status: "sent")

      get manage_ticket_order_refund_path(order.id), params: { ticket_ids: order.tickets.pluck(:id), keep_fees: "0" }
      expect(response.body).to include("Add $20.92 and refund")

      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_top", status: "succeeded"))
      post manage_ticket_order_refund_top_up_path(order.id), params: { ticket_ids: order.tickets.pluck(:id), keep_fees: "0" }
      expect(flash[:notice]).to eq("Added $20.92 and refunded Dana Scully.")
      expect(order.reload.status).to eq("refunded")
    end

    it "resends the tickets" do
      order = sold(1)
      expect { post manage_ticket_order_resend_path(order.id) }.to have_enqueued_job(TicketOrderConfirmationJob).with(order.id)
    end

    it "can't reach another theater's orders" do
      other_listing = create(:ticket_listing, organization: create(:organization, :pro))
      tier = other_listing.ticket_tiers.create!(name: "General", price_cents: 1_000)
      other = TicketCheckout.start!(listing: other_listing, quantities: { tier.id.to_s => "1" })
      TicketOrderSettlement.settle!(other)

      get manage_ticket_order_path(other.id)
      expect(response).to have_http_status(:not_found)
      post manage_ticket_order_refund_path(other.id), params: { ticket_ids: other.tickets.pluck(:id) }
      expect(response).to have_http_status(:not_found)
      expect(other.reload.status).to eq("paid")
    end
  end

  describe "the balance" do
    before do
      travel_to(5.days.ago) { sold(3) }
      listing.update!(released_at: 2.days.ago)
    end

    it "shows what's available and withdraws it" do
      get manage_ticket_balance_path
      expect(response.body).to include("Your CocoScout balance", "$60.00", "Keep it here (recommended)")

      allow(Stripe::Transfer).to receive(:create).and_return(double("transfer", id: "tr_w"))
      post manage_ticket_balance_withdraw_path, params: { amount: "45.50" }
      expect(flash[:notice]).to eq("$45.50 is on its way to your bank.")
      expect(TicketBalance.available_cents(org)).to eq(1_450)

      post manage_ticket_balance_withdraw_path, params: { amount: "lots" }
      expect(flash[:alert]).to eq("Enter an amount like 250.00.")
    end

    it "says what's safe to withdraw, and adds funds" do
      payee = create(:person, stripe_account_id: "acct_payee", payouts_enabled: true)
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: 1_500)
      PayoutBatchService.build_for(organization: org)

      get manage_ticket_balance_path
      expect(response.body).to include("Keep $15.00 for the next two weeks of payouts; you can safely withdraw $45.00", "Your open payout run", 'value="45.00"')

      org.update!(stripe_customer_id: "cus_sg", funding_payment_method_id: "pm_sg", funding_payment_method_type: "us_bank_account")
      allow(Stripe::PaymentIntent).to receive(:create).and_return(double("pi", id: "pi_top", status: "processing"))
      post manage_ticket_balance_top_up_path, params: { amount: "100" }
      expect(flash[:notice]).to eq("Adding $100.00 from your bank. It lands in 2 to 4 business days.")
      get manage_ticket_balance_path
      expect(response.body).to include("On its way")
    end

    it "lists payout runs already on their way instead of keeping money back for them" do
      org.payout_batches.create!(kind: "payout", status: "funding", trigger: "manual", funding_status: "processing", total_cents: 205_873)
      get manage_ticket_balance_path
      expect(response.body).to include("Already on its way, nothing here needed for it", "funded from your bank, the money&#39;s on its way", "$2,058.73")
    end

    it "turns automatic withdrawal on and off" do
      patch manage_ticket_balance_auto_withdraw_path, params: { auto_withdraw: "weekly" }
      expect(TicketingProfile.find_by!(organization: org).auto_withdraw).to eq("weekly")
      patch manage_ticket_balance_auto_withdraw_path, params: { auto_withdraw: "whenever" }
      expect(TicketingProfile.find_by!(organization: org).auto_withdraw).to eq("off")
    end

    it "shows on Ticketing home and at the top of Books, with Books linked from Money" do
      get manage_ticketing_path
      expect(response.body).to include("$60.00", manage_ticket_balance_path)
      get manage_money_index_path
      expect(response.body).to include(manage_money_books_path)
      expect(response.body).not_to include("Your CocoScout balance")
      get manage_money_books_path
      expect(response.body).to include("Your CocoScout balance", "$60.00", manage_ticket_balance_path)
      expect(manage_ticket_balance_path).to start_with("/manage/money/books/")
    end

    it "is what a payout run spends first" do
      payee = create(:person, stripe_account_id: "acct_payee", payouts_enabled: true)
      PayoutLedgerEntry.post!(organization: org, payee: payee, entry_type: "earning", amount_cents: 5_000)
      batch = PayoutBatchService.build_for(organization: org)
      org.update!(funding_payment_method_id: "pm_1")

      get manage_payout_batch_path(batch)
      expect(response.body).to include("Paid from your CocoScout balance: $50.00")
    end
  end

  it "reports taxes collected, on screen and as a CSV" do
    TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
    sold(2)

    get manage_ticket_taxes_path
    expect(response.body).to include("Sales tax", "10.25%", "$4.10 to pay")
    get manage_ticket_taxes_path(format: :csv)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Sales tax,10.25%,,40.00,0.00,40.00,4.10,0.00,4.10")
  end

  # Tim (2026-10-02): canceling happens in Shows & Events; its cancel screen
  # carries the ticket buyers and their email.
  it "cancels a show in Shows & Events, refunding ticket buyers with an email read first" do
    sold(1)
    show = listing.show
    get manage_ticket_listing_path(listing)
    expect(response.body).to include(manage_cancel_show_form_path(show.production, show))

    get manage_cancel_show_form_path(show.production, show)
    expect(response.body).to include("Refund ticket buyers and email them", "1 buyer", "Dana Scully", "{{show_title}} on {{show_date}} is canceled")

    perform_enqueued_jobs do
      patch manage_cancel_show_path(show.production, show),
            params: { scope: "this", notify_cast: "0", refund_tickets: "1", ticket_email_subject: "Canceled", ticket_email_body: "Hi {{first_name}}" }
    end
    expect(flash[:notice]).to include("Refunds are on their way to 1 ticket buyer.")
    expect([ show.reload.canceled, listing.reload.status ]).to eq([ true, "canceled" ])
    expect(listing.ticket_orders.sole.status).to eq("refunded")
  end

  it "won't delete a date that sold tickets; it points to canceling instead" do
    sold(1)
    show = listing.show
    delete manage_delete_show_path(show.production, show), params: { scope: "this" }
    expect(response).to redirect_to(manage_cancel_show_form_path(show.production, show))
    expect(flash[:alert]).to include("can't be deleted. Cancel it instead")
    expect(Show.exists?(show.id)).to be(true)
  end

  it "cancels the show but leaves tickets alone when asked, and refunds them later from the same screen" do
    sold(1)
    show = listing.show
    patch manage_cancel_show_path(show.production, show), params: { scope: "this", notify_cast: "0", refund_tickets: "0" }
    expect([ show.reload.canceled, listing.reload.status ]).to eq([ true, "on_sale" ])
    expect(listing.selling?).to be(false)

    get manage_cancel_show_form_path(show.production, show)
    expect(response.body).to include("Ticket Buyers", "1 person still holds tickets", "Refund 1 buyer")
    post manage_ticket_listing_cancel_path(listing), params: { subject: "Canceled", body: "Hi {{first_name}}" }
    expect(flash[:notice]).to eq("Refunds are on their way to 1 ticket buyer.")
    expect(listing.reload.status).to eq("canceled")
  end
end
