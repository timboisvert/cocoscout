# frozen_string_literal: true

require "rails_helper"

# CocoScout's take from ticketing on superadmin Finances.
RSpec.describe TicketingFinances do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org) }
  let(:listing) { create(:ticket_listing, organization: org, show: create(:show, production: production)) }
  let(:later) { create(:ticket_listing, organization: org, show: create(:show, production: production, date_and_time: 2.weeks.from_now)) }

  def paid_order(listing, **attrs)
    TicketOrder.create!({ organization: org, ticket_listing: listing, status: "paid", paid_at: Time.current, channel: "online",
                          money_path: "cocoscout", fee_mode: "buyer", buyer_name: "Dana", buyer_email: "dana@example.com",
                          subtotal_cents: 4_000, total_cents: 4_253, platform_fee_cents: 100, processing_cents: 153,
                          buyer_fee_cents: 253, org_net_cents: 4_000, stripe_fee_cents: 153 }.merge(attrs))
  end

  it "counts an exchanged order's money once, on the purchase" do
    original = paid_order(listing)
    original.update!(status: "exchanged")
    paid_order(later, exchanged_from: original, stripe_fee_cents: nil)

    totals = described_class.new.totals
    expect([ totals.orders, totals.gross_cents, totals.platform_fee_cents, totals.processing_charged_cents, totals.stripe_fee_cents, totals.missing_fee_count ])
      .to eq([ 1, 4_253, 100, 153, 153, 0 ])
  end
end
