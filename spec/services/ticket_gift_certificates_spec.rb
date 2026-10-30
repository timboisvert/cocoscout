# frozen_string_literal: true

require "rails_helper"

# A gift certificate paying at checkout: it's payment, not a discount. The
# total stands; the certificate covers what it can and the card pays the
# rest; its money is held like seats, spent when the order settles, and
# never reaches the theater's balance (they took it when they sold it).
RSpec.describe TicketGiftCertificates do
  let(:org) { create(:organization, :pro) }
  let(:production) { create(:production, organization: org, name: "Late Night Cabaret") }
  let(:show) { create(:show, production: production, date_and_time: 10.days.from_now.change(hour: 22)) }
  let(:listing) { create(:ticket_listing, organization: org, show: show) }
  let!(:general) { listing.ticket_tiers.create!(name: "General", price_cents: 2_500, quantity: 20) }
  let(:certificate) { org.ticket_gift_certificates.create!(amount_cents: 5_000, recipient_name: "Dana Whitfield") }

  def checkout(count = 3)
    TicketCheckout.start!(listing: listing, quantities: { general.id.to_s => count.to_s }).tap do |order|
      order.update!(buyer_name: "Dana Whitfield", buyer_email: "dana@example.com")
    end
  end

  def balance(key)
    ChartOfAccounts.account(org, key).natural_balance_cents
  end

  it "makes codes people can read out, and finds them however they're typed" do
    expect(certificate.code).to match(TicketGiftCertificate::CODE_FORMAT)
    expect(certificate.code.delete_prefix("GIFT-")).not_to match(/[01IO]/)
    typed = certificate.code.downcase.delete("-").insert(4, " ")
    expect(TicketGiftCertificate.normalize_code(typed)).to eq(certificate.code)
  end

  it "pays part of the order and leaves the rest to the card, with processing on the card's part only" do
    order = checkout # 3 × $25 = $75; buyer pays fees: $79.09
    expect(order.total_cents).to eq(7_909)
    quoted_processing = order.processing_cents

    described_class.apply!(order.ticket_purchase, certificate.code)
    order.reload
    purchase = order.ticket_purchase

    expect([ purchase.gift_certificate_cents, purchase.card_cents, order.gift_certificate_cents, order.total_cents ]).to eq([ 5_000, 2_909, 5_000, 7_909 ])
    expect(order.processing_cents).to eq(TicketPricing.processing_cents(2_909))
    expect(order.processing_cents).to be < quoted_processing
    expect(order.org_net_cents).to eq(7_909 - order.processing_cents - 150)
    # The money is held on the certificate at once.
    expect(certificate.reload.remaining_cents).to eq(0)
    expect(certificate.redemptions.held.sole.amount_cents).to eq(5_000)
  end

  it "covers the whole order when it has enough, keeping the rest for next time" do
    big = org.ticket_gift_certificates.create!(amount_cents: 10_000)
    order = checkout
    described_class.apply!(order.ticket_purchase, big.code)
    order.reload

    expect([ order.ticket_purchase.card_cents, order.gift_certificate_cents, order.processing_cents ]).to eq([ 0, 7_909, 0 ])
    expect(big.reload.remaining_cents).to eq(2_091)
  end

  it "gives one bland answer for a code that's wrong, spent or voided" do
    order = checkout
    expect { described_class.apply!(order.ticket_purchase, "GIFT-AAAA-BBBB-CCCC") }.to raise_error(described_class::Error, described_class::WRONG_CODE)
    certificate.update!(voided_at: Time.current)
    expect { described_class.apply!(order.ticket_purchase, certificate.code) }.to raise_error(described_class::Error, described_class::WRONG_CODE)
  end

  it "tells a real code where it does work when this show isn't covered" do
    other = create(:production, organization: org, name: "Winter Follies")
    certificate.update!(scope: "some")
    certificate.scopes.create!(production: other)
    order = checkout
    expect { described_class.apply!(order.ticket_purchase, certificate.code) }
      .to raise_error(described_class::Error, "This certificate is good for Winter Follies, not Late Night Cabaret.")
    expect(certificate.reload.remaining_cents).to eq(5_000)
  end

  it "covers a production's date when the scope names that date, and not its other dates" do
    other_show = create(:show, production: production, date_and_time: 12.days.from_now.change(hour: 22))
    other_listing = create(:ticket_listing, organization: org, show: other_show)
    certificate.update!(scope: "some")
    certificate.scopes.create!(production: production, ticket_listing: listing)
    expect(certificate.covers?(listing)).to be(true)
    expect(certificate.covers?(other_listing)).to be(false)
    expect(certificate.good_for_words).to eq("Late Night Cabaret (1 date)")
  end

  it "follows the total when the order changes, and puts the money back when the code comes off" do
    bottle = create(:ticket_product, organization: org, name: "Champagne", price_cents: 4_500)
    ProductionTicketing.for(production).production_ticketing_products.create!(ticket_product: bottle, position: 0)
    small = org.ticket_gift_certificates.create!(amount_cents: 8_000)
    order = checkout(1) # $25 → $26.33
    purchase = order.ticket_purchase
    described_class.apply!(purchase, small.code)
    expect(small.reload.remaining_cents).to eq(8_000 - order.reload.total_cents)

    TicketCheckout.set_items!(order, { bottle.id.to_s => "1" })
    purchase.reload
    expect(purchase.gift_certificate_cents).to eq(purchase.total_cents)
    expect(small.reload.remaining_cents).to eq(8_000 - purchase.total_cents)

    described_class.remove!(purchase)
    purchase.reload
    expect([ purchase.gift_certificate_cents, purchase.ticket_gift_certificate_id ]).to eq([ 0, nil ])
    expect(small.reload.remaining_cents).to eq(8_000)
    expect(order.reload.processing_cents).to eq(TicketPricing.processing_cents(purchase.total_cents))
  end

  it "puts the money back when the hold runs out" do
    order = checkout
    described_class.apply!(order.ticket_purchase, certificate.code)
    order.ticket_purchase.update!(expires_at: 1.minute.ago)
    order.update!(expires_at: 1.minute.ago)

    ExpireTicketHoldsJob.perform_now
    expect(certificate.reload.remaining_cents).to eq(5_000)
    expect(certificate.redemptions.sole.status).to eq("released")
    expect(order.reload.status).to eq("expired")
  end

  describe "settling" do
    it "spends the certificate, credits the balance only what the card paid, and keeps the books square" do
      order = checkout
      purchase = order.ticket_purchase
      described_class.apply!(purchase, certificate.code)
      order.reload

      TicketPurchaseSettlement.settle!(purchase, payment_intent_id: "pi_1", charge_id: "ch_1", amount_cents: 2_909)
      order.reload
      expect(order.status).to eq("paid")
      expect(certificate.reload.redemptions.sole.status).to eq("redeemed")
      expect(certificate.remaining_cents).to eq(0)

      # The balance gets the card's part less fees; the certificate's $50 never lands there.
      expect(OrgCashEntry.where(source: order).sole.amount_cents).to eq(order.org_net_cents - 5_000)
      expect(balance(:gift_certificates_outstanding)).to eq(-5_000)
      expect(balance(:advance_ticket_sales)).to eq(7_500)
      expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
      # The show's financials still see three $25 tickets.
      expect(listing.show.reload.show_financials.ticket_revenue.to_f).to eq(75.0)
    end

    it "refuses a card payment for anything but what the card owes" do
      order = checkout
      purchase = order.ticket_purchase
      described_class.apply!(purchase, certificate.code)
      allow(Stripe::Refund).to receive(:create)

      TicketPurchaseSettlement.settle!(purchase, payment_intent_id: "pi_1", charge_id: "ch_1", amount_cents: 7_909)
      expect(Stripe::Refund).to have_received(:create).with(hash_including(payment_intent: "pi_1"), anything)
      expect(purchase.reload.status).to eq("canceled")
      expect(certificate.reload.remaining_cents).to eq(5_000)
    end

    it "settles with no card at all when the certificate covers everything, and charges our fee to the balance" do
      big = org.ticket_gift_certificates.create!(amount_cents: 10_000)
      order = checkout
      purchase = order.ticket_purchase
      described_class.apply!(purchase, big.code)

      TicketPurchaseSettlement.settle!(purchase)
      order.reload
      expect([ order.status, order.gift_certificate_cents, order.processing_cents ]).to eq([ "paid", 7_909, 0 ])
      # 50¢ × 3 tickets comes out of the theater's balance; nothing came in.
      expect(OrgCashEntry.where(source: order).sole.amount_cents).to eq(-150)
      expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
    end

    it "refunds a late card payment when the certificate's money was spent elsewhere meanwhile" do
      order = checkout
      purchase = order.ticket_purchase
      described_class.apply!(purchase, certificate.code)
      purchase.update!(expires_at: 1.minute.ago)
      order.update!(expires_at: 1.minute.ago)
      ExpireTicketHoldsJob.perform_now
      # Another buyer spends the same certificate.
      other = checkout
      described_class.apply!(other.ticket_purchase, certificate.code)
      TicketPurchaseSettlement.settle!(other.ticket_purchase, payment_intent_id: "pi_other", amount_cents: 2_909)
      allow(Stripe::Refund).to receive(:create)

      TicketPurchaseSettlement.settle!(purchase.reload, payment_intent_id: "pi_late", charge_id: "ch_late", amount_cents: 2_909)
      expect(Stripe::Refund).to have_received(:create).with(hash_including(payment_intent: "pi_late"), anything)
      expect(purchase.reload.status).to eq("canceled")
      expect(other.reload.status).to eq("paid")
    end
  end

  describe "refunding" do
    before { allow(Stripe::Refund).to receive(:create).and_return(Stripe::Refund.construct_from(id: "re_1")) }

    it "puts the certificate's part back on the certificate and only the card's part on the card" do
      order = checkout
      purchase = order.ticket_purchase
      described_class.apply!(purchase, certificate.code)
      TicketPurchaseSettlement.settle!(purchase, payment_intent_id: "pi_1", charge_id: "ch_1", amount_cents: 2_909)
      order.reload

      refund = TicketOrderRefund.issue!(order, by: nil)
      expect(refund.amount_cents).to eq(7_909)
      expect(refund.gift_certificate_cents).to eq(5_000)
      expect(Stripe::Refund).to have_received(:create).with(hash_including(amount: 2_909), anything)
      expect(certificate.reload.remaining_cents).to eq(5_000)
      expect(certificate.redemptions.where(status: "refunded").sole.amount_cents).to eq(5_000)
      # The balance gives up only what the card put in, less our returned 50¢s.
      expect(refund.org_debit_cents).to eq(2_909 - 150)
      expect(LedgerPosting.trial_balance(org).values.sum).to eq(0)
      expect(balance(:gift_certificates_outstanding)).to eq(0)
    end

    it "refunds one ticket to the certificate first, so cash never comes out for certificate money" do
      order = checkout
      purchase = order.ticket_purchase
      described_class.apply!(purchase, certificate.code)
      TicketPurchaseSettlement.settle!(purchase, payment_intent_id: "pi_1", charge_id: "ch_1", amount_cents: 2_909)
      order.reload

      refund = TicketOrderRefund.issue!(order, ticket_ids: [ order.tickets.first.id ], by: nil)
      expect(refund.gift_certificate_cents).to eq(refund.amount_cents)
      expect(Stripe::Refund).not_to have_received(:create)
      expect(certificate.reload.remaining_cents).to eq(refund.amount_cents)
    end

    it "won't move tickets a certificate paid for" do
      order = checkout
      described_class.apply!(order.ticket_purchase, certificate.code)
      TicketPurchaseSettlement.settle!(order.ticket_purchase, payment_intent_id: "pi_1", amount_cents: 2_909)
      other_show = create(:show, production: production, date_and_time: 12.days.from_now.change(hour: 22))
      target = create(:ticket_listing, organization: org, show: other_show)
      target.ticket_tiers.create!(name: "General", price_cents: 2_500, quantity: 20)

      expect { TicketOrderExchange.plan(order.reload, target: target) }
        .to raise_error(TicketOrderExchange::Error, /can't be moved yet/)
    end
  end
end
