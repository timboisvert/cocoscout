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

      it "bills usage only on Pro, and never when a superadmin comped it" do
        expect(Stripe::Billing::MeterEvent).not_to receive(:create)
        org.update!(comped_usage: true)
        expect(described_class.report_activation!(activation)).to eq(:not_billed)
        org.update!(comped_usage: false, comped_indefinitely: false, comped_until: nil, subscription_status: "canceled")
        expect(described_class.report_activation!(activation)).to eq(:not_billed)
        expect(activation.reload.reported_at).to be_nil
      end

      it "bills usage for an org comped on the plan but not on usage" do
        org.update!(comped_indefinitely: true, comped_usage: false)
        allow(Stripe::Billing::MeterEvent).to receive(:create)
        expect(described_class.report_activation!(activation)).to eq(:reported)
      end

      it "skips an org with no Stripe customer" do
        org.update!(stripe_customer_id: nil)
        expect(Stripe::Billing::MeterEvent).not_to receive(:create)
        expect(described_class.report_activation!(activation)).to eq(:not_configured)
      end
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

  describe ".sync_usage_subscription!" do
    it "cancels the usage subscription of an org that stopped paying for usage, without a final bill" do
      org.update!(staffing_subscription_id: "sub_usage", comped_usage: true)
      expect(Stripe::Subscription).to receive(:cancel).with("sub_usage")
      expect(described_class.sync_usage_subscription!(org)).to be(true)
      expect(org.reload.staffing_subscription_id).to be_nil
    end

    it "leaves a paying org's usage subscription alone" do
      org.update!(staffing_subscription_id: "sub_usage")
      expect(Stripe::Subscription).not_to receive(:cancel)
      expect(described_class.sync_usage_subscription!(org)).to be(false)
    end
  end
end
