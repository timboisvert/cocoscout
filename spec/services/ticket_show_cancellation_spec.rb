# frozen_string_literal: true

require "rails_helper"

# Canceling a show that sold tickets, a disputed charge, and the taxes report.
RSpec.describe TicketShowCancellation do
  include ActiveJob::TestHelper

  let(:org) { create(:organization, :pro, name: "Stars & Garters") }
  let(:listing) { create(:ticket_listing, organization: org) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_000) }
  let(:manager) { create(:user) }

  before { allow(Stripe::Refund).to receive(:create).and_return(double("refund", id: "re_1")) }

  def sold(count, name:, email:)
    order = TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s })
    order.update!(buyer_name: name, buyer_email: email)
    TicketOrderSettlement.settle!(order, payment_intent_id: "pi_#{name.parameterize}")
    order.reload
  end

  it "drafts the email and lists who's refunded, before anything happens" do
    sold(2, name: "Dana Scully", email: "dana@example.com")
    sold(1, name: "Fox Mulder", email: "fox@example.com")

    draft = described_class.draft(listing)
    expect(draft.orders.map(&:buyer_name)).to eq([ "Dana Scully", "Fox Mulder" ])
    expect(draft.refund_cents).to eq(4_253 + 2_142)
    expect(draft.subject).to eq("{{show_title}} on {{show_date}} is canceled")
    expect(draft.body).to start_with("Hi {{first_name}}")
    expect(draft.body).not_to include("<p>")
  end

  it "stops sales, refunds everyone, and sends each buyer the manager's words" do
    dana = sold(2, name: "Dana Scully", email: "dana@example.com")
    fox = sold(1, name: "Fox Mulder", email: "fox@example.com")

    perform_enqueued_jobs do
      described_class.start!(listing, subject: "{{show_title}} is off", body: "Hi {{first_name}},\n\nYou get {{refund_amount}} back.",
                                      by: manager, cancel_show: true)
    end

    expect([ listing.reload.status, listing.show.reload.canceled ]).to eq([ "canceled", true ])
    expect([ dana.reload.status, fox.reload.status ]).to eq(%w[refunded refunded])
    expect(dana.ticket_refunds.sole.refunded_by).to eq(manager)

    mail = ActionMailer::Base.deliveries.find { |m| m.to == [ "dana@example.com" ] }
    expect(mail.subject).to eq("#{listing.display_title} is off")
    expect(mail.html_part&.body&.decoded || mail.body.decoded).to include("Hi Dana,", "You get $42.53 back.")
  end

  it "is safe to run again: refunded orders are left alone" do
    sold(1, name: "Dana Scully", email: "dana@example.com")
    listing.update!(status: "canceled")
    2.times { TicketShowCancellationJob.perform_now(listing.id, "s", "b") }
    expect(Stripe::Refund).to have_received(:create).once
  end

  describe TicketDispute do
    it "takes a disputed charge and Stripe's fee out of the theater's money, and gives both back on a win" do
      order = sold(1, name: "Dana Scully", email: "dana@example.com")
      dispute = double("dispute", payment_intent: "pi_dana-scully", charge: nil, amount: 2_142, status: "needs_response")

      TicketDispute.handle(dispute, "charge.dispute.created")
      expect(OrgCashEntry.balance_cents(org)).to eq(2_000 - 3_642)
      expect(TicketDispute.open?(order)).to be(true)
      expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)

      TicketDispute.handle(double("dispute", payment_intent: "pi_dana-scully", charge: nil, amount: 2_142, status: "won"), "charge.dispute.closed")
      expect(OrgCashEntry.balance_cents(org)).to eq(2_000)
      expect(TicketDispute.open?(order)).to be(false)
    end
  end

  describe TicketTaxReport do
    it "adds up what was collected and refunded, for paid orders only" do
      TicketTaxSetting.save!(org, name: "Sales tax", percent: "10.25", mode: "added")
      order = sold(2, name: "Dana Scully", email: "dana@example.com")
      TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => "3" }) # never paid
      TicketOrderRefund.issue!(order, ticket_ids: [ order.tickets.first.id ])

      report = described_class.new(org, from: Date.current.beginning_of_month, to: Date.current.end_of_month)
      row = report.rows.sole
      expect([ row.name, row.rate_label, row.gross_cents, row.collected_cents, row.refunded_cents, row.net_cents ])
        .to eq([ "Sales tax", "10.25%", 2_000, 410, -205, 205 ])
      expect(report.to_csv.lines.last.strip).to eq("Sales tax,10.25%,,20.00,0.00,20.00,4.10,-2.05,2.05")
    end
  end
end
