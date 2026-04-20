# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrgPayout, type: :model do
  subject { build(:org_payout) }

  describe "validations" do
    it { is_expected.to be_valid }

    it "requires amount_cents" do
      subject.amount_cents = nil
      expect(subject).not_to be_valid
    end

    it "requires amount_cents > 0" do
      subject.amount_cents = 0
      expect(subject).not_to be_valid
    end

    it "requires valid payment_method" do
      subject.payment_method = "bitcoin"
      expect(subject).not_to be_valid
    end

    it "requires valid status" do
      subject.status = "unknown"
      expect(subject).not_to be_valid
    end

    it "requires valid payout_type" do
      subject.payout_type = "invalid"
      expect(subject).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to organization" do
      expect(subject.organization).to be_present
    end

    it "optionally belongs to course_offering" do
      subject.course_offering = nil
      expect(subject).to be_valid
    end
  end

  describe "scopes" do
    let!(:pending_payout) { create(:org_payout, :pending) }
    let!(:paid_payout) { create(:org_payout, status: "paid") }

    it ".pending returns pending payouts" do
      expect(described_class.pending).to contain_exactly(pending_payout)
    end

    it ".paid returns paid payouts" do
      expect(described_class.paid).to contain_exactly(paid_payout)
    end

    it ".for_course filters by course_offering" do
      co = paid_payout.course_offering
      expect(described_class.for_course(co)).to contain_exactly(paid_payout)
    end
  end

  describe "#mark_paid!" do
    let(:payout) { create(:org_payout, :pending) }
    let(:user) { create(:user) }

    it "marks as paid with timestamp and user" do
      payout.mark_paid!(user: user)
      payout.reload
      expect(payout.status).to eq("paid")
      expect(payout.paid_at).to be_present
      expect(payout.paid_by_user).to eq(user)
    end
  end

  describe "#formatted_amount" do
    it "formats whole dollar amounts without decimals" do
      subject.amount_cents = 5000
      expect(subject.formatted_amount).to eq("$50")
    end

    it "formats amounts with cents" do
      subject.amount_cents = 4750
      expect(subject.formatted_amount).to eq("$47.50")
    end

    it "returns $0 for zero" do
      subject.amount_cents = 0
      expect(subject.formatted_amount).to eq("$0")
    end
  end

  describe ".owed_cents_for_course" do
    let(:course_offering) { create(:course_offering) }

    it "calculates 95% of confirmed registrations only" do
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "refunded")

      # Only confirmed: 20000 * 0.95 = 19000 (refunded is ignored, not subtracted)
      expect(described_class.owed_cents_for_course(course_offering)).to eq(19000)
    end

    it "returns 0 when no registrations" do
      expect(described_class.owed_cents_for_course(course_offering)).to eq(0)
    end
  end

  describe ".paid_cents_for_course" do
    let(:course_offering) { create(:course_offering) }

    it "sums paid payouts for the course" do
      org = course_offering.organization
      create(:org_payout, organization: org, course_offering: course_offering, amount_cents: 5000, status: "paid")
      create(:org_payout, organization: org, course_offering: course_offering, amount_cents: 3000, status: "paid")
      create(:org_payout, :pending, organization: org, course_offering: course_offering, amount_cents: 1000)

      expect(described_class.paid_cents_for_course(course_offering)).to eq(8000)
    end
  end

  describe ".balance_cents_for_course" do
    let(:course_offering) { create(:course_offering) }

    it "returns owed minus paid" do
      org = course_offering.organization
      create(:course_registration, course_offering: course_offering, amount_cents: 10000, status: "confirmed")
      create(:org_payout, organization: org, course_offering: course_offering, amount_cents: 5000, status: "paid")

      # owed = 10000 * 0.95 = 9500, paid = 5000, balance = 4500
      expect(described_class.balance_cents_for_course(course_offering)).to eq(4500)
    end
  end
end
