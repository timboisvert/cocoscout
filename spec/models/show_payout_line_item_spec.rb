# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShowPayoutLineItem, type: :model do
  let(:org) { create(:organization) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production) }
  let(:payout) { ShowPayout.create!(show: show, status: "awaiting_payout", calculated_at: Time.current, total_payout: 0) }

  def line_item(**attrs)
    ShowPayoutLineItem.create!({ show_payout: payout, payee: create(:person), amount: 50 }.merge(attrs))
  end

  describe ".paid / .unpaid" do
    it "treats a fresh item as unpaid" do
      li = line_item
      expect(ShowPayoutLineItem.unpaid).to include(li)
      expect(ShowPayoutLineItem.paid).not_to include(li)
    end

    it "counts a manually-paid item as paid" do
      li = line_item(manually_paid: true)
      expect(ShowPayoutLineItem.paid).to include(li)
      expect(ShowPayoutLineItem.unpaid).not_to include(li)
    end

    it "counts a Stripe-run-paid item as paid (what the old scopes missed)" do
      li = line_item(payout_reference_id: "tr_123", payout_status: "success")
      expect(li).to be_paid
      expect(ShowPayoutLineItem.paid).to include(li)
      expect(ShowPayoutLineItem.unpaid).not_to include(li)
    end

    it "does not count a pending/failed run item as paid" do
      li = line_item(payout_reference_id: "tr_123", payout_status: "pending")
      expect(ShowPayoutLineItem.unpaid).to include(li)
      expect(ShowPayoutLineItem.paid).not_to include(li)
    end
  end

  describe "offline payment methods (paid another way)" do
    it "offers zelle and venmo as manual methods with proper labels" do
      expect(ShowPayoutLineItem::MANUAL_PAYMENT_METHODS).to include("zelle", "venmo")
      expect(ShowPayoutLineItem::PAYMENT_METHODS).to include("zelle", "venmo")

      li = line_item
      expect(li.tap { |i| i.payment_method = "zelle" }.payment_method_label).to eq("Zelle")
      expect(li.tap { |i| i.payment_method = "venmo" }.payment_method_label).to eq("Venmo")
    end

    it "marks a payee paid offline, offsets their ledger balance, and moves no money through Stripe" do
      person = create(:person)
      li = line_item(payee: person, amount: 50)
      li.sync_earning_ledger_entry! # they're owed $50
      expect(org.payout_balance_cents_for(person)).to eq(5000)

      li.mark_as_offline_paid!(create(:user), method: "zelle", notes: "Zelle #123")

      expect(li.reload).to be_paid
      expect(li.manually_paid?).to be(true)
      expect(li.payment_method).to eq("zelle")
      expect(li.payment_notes).to eq("Zelle #123")
      # The offsetting payout entry zeroes what we owe them.
      expect(org.payout_balance_cents_for(person)).to eq(0)
      expect(PayoutLedgerEntry.where(source: li, entry_type: "payout").sum(:amount_cents)).to eq(-5000)
      # Not a Stripe/bank movement: no payout run item, no transfer reference.
      expect(PayoutBatchItem.count).to eq(0)
      expect(li.payout_reference_id).to be_nil
    end
  end
end
