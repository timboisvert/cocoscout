# frozen_string_literal: true

require "rails_helper"

RSpec.describe PerformerMeterService do
  let(:org) { create(:organization, :pro, stripe_customer_id: "cus_meter") }
  let(:person) { create(:person, name: "Metered Mae") }
  let(:activation) { PerformerActivation.record!(organization: org, person: person, month: Date.current) }

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
      before { allow(described_class).to receive(:active_event_name).and_return("performer_active") }

      it "sends one idempotent meter event of value 1 and marks it reported" do
        expect(Stripe::Billing::MeterEvent).to receive(:create).with(
          hash_including(
            event_name: "performer_active",
            identifier: "performer_active:#{org.id}:#{person.id}:#{Date.current.beginning_of_month.iso8601}",
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

  describe ".reconcile_month!" do
    before { allow(described_class).to receive(:active_event_name).and_return("performer_active") }

    it "re-sends only activations that haven't been metered yet" do
      already = PerformerActivation.record!(organization: org, person: person, month: Date.current)
      already.update_column(:reported_at, Time.current)
      pending = PerformerActivation.record!(organization: org, person: create(:person), month: Date.current)

      expect(described_class).to receive(:report_activation!).once do |activation|
        expect(activation).to eq(pending)
        :reported
      end

      expect(described_class.reconcile_month!(org)).to eq(:reconciled)
    end
  end
end
