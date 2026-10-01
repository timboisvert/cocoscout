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

      get manage_ticket_order_refund_path(order.id), params: { ticket_ids: ids }
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

    it "hides refunds after the show unless the theater allows them" do
      order = sold(1)
      listing.show.update!(date_and_time: 1.hour.ago)

      get manage_ticket_order_path(order.id)
      expect(response.body).to include("refunds after the show are off")
      expect(response.body).not_to include("Review refund")
      get manage_ticket_order_refund_path(order.id), params: { ticket_ids: order.tickets.pluck(:id) }
      expect(response).to redirect_to(manage_ticket_order_path(order.id))

      patch manage_ticketing_settings_path, params: { ticketing_profile: { refunds_after_show: "1" } }
      expect(TicketingProfile.find_by!(organization: org).refunds_after_show).to be(true)
      get manage_ticket_order_path(order.id)
      expect(response.body).to include("Review refund")
    end

    it "won't cancel a show that has started" do
      sold(1)
      listing.show.update!(date_and_time: 1.hour.ago)
      get manage_ticket_listing_cancel_path(listing)
      expect(flash[:alert]).to include("already started")
      post manage_ticket_listing_cancel_path(listing), params: { subject: "x", body: "y" }
      expect(listing.reload.status).to eq("on_sale")
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

    it "turns automatic withdrawal on and off" do
      patch manage_ticket_balance_auto_withdraw_path, params: { auto_withdraw: "weekly" }
      expect(TicketingProfile.find_by!(organization: org).auto_withdraw).to eq("weekly")
      patch manage_ticket_balance_auto_withdraw_path, params: { auto_withdraw: "whenever" }
      expect(TicketingProfile.find_by!(organization: org).auto_withdraw).to eq("off")
    end

    it "shows on Ticketing home and the Money hub" do
      get manage_ticketing_path
      expect(response.body).to include("$60.00", manage_ticket_balance_path)
      get manage_money_index_path
      expect(response.body).to include("Your CocoScout balance")
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

  it "cancels a show after showing who's refunded and the email" do
    sold(1)
    get manage_ticket_listing_cancel_path(listing)
    expect(response.body).to include("Dana Scully", "Cancel and refund everyone", "How it reads for Dana Scully")

    perform_enqueued_jobs do
      post manage_ticket_listing_cancel_path(listing), params: { subject: "Canceled", body: "Hi {{first_name}}", cancel_show: "1" }
    end
    expect(flash[:notice]).to eq("Ticket sales canceled. Refunds are on their way to 1 buyer.")
    expect(listing.reload.status).to eq("canceled")
    expect(listing.ticket_orders.sole.status).to eq("refunded")
  end
end
