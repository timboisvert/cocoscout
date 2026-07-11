# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffMeterService do
  let(:org) { create(:organization, :pro, stripe_customer_id: "cus_meter") }
  let(:person) { create(:person, name: "Metered Mo") }
  let(:activation) { StaffActivation.record!(organization: org, person: person, month: Date.current) }

  describe ".report_activation!" do
    context "when the meter isn't configured" do
      before { allow(described_class).to receive(:active_event_name).and_return(nil) }

      it "no-ops" do
        expect(Stripe::Billing::MeterEvent).not_to receive(:create)
        expect(described_class.report_activation!(activation)).to eq(:not_configured)
        expect(activation.reload.reported_at).to be_nil
      end
    end

    context "when configured" do
      before { allow(described_class).to receive(:active_event_name).and_return("staff_active") }

      it "sends one idempotent meter event of value 1 and marks it reported" do
        expect(Stripe::Billing::MeterEvent).to receive(:create).with(
          hash_including(
            event_name: "staff_active",
            identifier: "staff_active:#{org.id}:#{person.id}:#{Date.current.beginning_of_month.iso8601}",
            payload: { stripe_customer_id: "cus_meter", value: "1" }
          )
        )

        expect(described_class.report_activation!(activation)).to eq(:reported)
        expect(activation.reload.reported_at).to be_present
      end

      it "skips an org with no Stripe customer" do
        org.update!(stripe_customer_id: nil)
        expect(Stripe::Billing::MeterEvent).not_to receive(:create)
        expect(described_class.report_activation!(activation)).to eq(:not_configured)
      end
    end
  end

  describe ".report_extra_payments!" do
    let(:batch) { org.payout_batches.create!(trigger: "manual", status: "completed", kind: "staff_pay", extra_payment_fee_cents: 300) }

    context "when configured" do
      before { allow(described_class).to receive(:extra_payment_event_name).and_return("staff_extra") }

      it "reports the fee as $1 units and marks the batch metered" do
        expect(Stripe::Billing::MeterEvent).to receive(:create).with(
          hash_including(event_name: "staff_extra", identifier: "staff_extra:batch:#{batch.id}",
                         payload: { stripe_customer_id: "cus_meter", value: "3" })
        )
        expect(described_class.report_extra_payments!(batch)).to eq(:reported)
        expect(batch.reload.fee_metered_at).to be_present
      end
    end

    it "does nothing when there's no fee" do
      allow(described_class).to receive(:extra_payment_event_name).and_return("staff_extra")
      free = org.payout_batches.create!(trigger: "manual", status: "completed", kind: "staff_pay", extra_payment_fee_cents: 0)
      expect(Stripe::Billing::MeterEvent).not_to receive(:create)
      expect(described_class.report_extra_payments!(free)).to eq(:nothing_to_report)
    end
  end

  describe ".reconcile_month!" do
    before { allow(described_class).to receive(:active_event_name).and_return("staff_active") }

    it "re-sends only activations that haven't been metered yet" do
      already = StaffActivation.record!(organization: org, person: person, month: Date.current)
      already.update_column(:reported_at, Time.current)
      pending_person = create(:person, name: "Pending Pat")
      StaffActivation.record!(organization: org, person: pending_person, month: Date.current)

      expect(Stripe::Billing::MeterEvent).to receive(:create).once
      described_class.reconcile_month!(org)
    end
  end
end
