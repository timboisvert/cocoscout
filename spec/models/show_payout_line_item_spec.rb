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
end
