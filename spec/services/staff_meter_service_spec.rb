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
    it "cancels the usage subscription of an org whose usage was comped, without a final bill" do
      org.update!(staffing_subscription_id: "sub_usage", comped_usage: true)
      expect(Stripe::Subscription).to receive(:cancel).with("sub_usage", { invoice_now: false, prorate: false })
      expect(described_class.sync_usage_subscription!(org)).to be(true)
      expect(org.reload.staffing_subscription_id).to be_nil
    end

    it "sends a last bill for what was metered when an org leaves Pro" do
      org.update!(staffing_subscription_id: "sub_usage", comped_indefinitely: false, comped_until: 1.day.ago)
      expect(Stripe::Subscription).to receive(:cancel).with("sub_usage", { invoice_now: true, prorate: false })
      expect(described_class.sync_usage_subscription!(org)).to be(true)
    end

    it "leaves a paying org's usage subscription alone" do
      org.update!(staffing_subscription_id: "sub_usage")
      expect(Stripe::Subscription).not_to receive(:cancel)
      expect(described_class.sync_usage_subscription!(org)).to be(false)
    end
  end

  describe ".ensure_staffing_subscription!" do
    def stripe_subscriptions(*subs)
      allow(Stripe::Subscription).to receive(:list).and_return(Stripe::ListObject.construct_from(data: subs))
    end

    before { allow(SubscriptionPlan).to receive(:staffing_subscription_items).and_return([ { price: "price_staff" } ]) }

    it "bills calendar months, the months the Billing page counts" do
      stripe_subscriptions
      expect(Stripe::Subscription).to receive(:create)
        .with(hash_including(customer: "cus_meter", billing_cycle_anchor_config: { day_of_month: 1 }, metadata: hash_including(kind: "staffing")),
              hash_including(idempotency_key: "staffing-subscription-#{org.id}-cus_meter-#{Date.current.iso8601}"))
        .and_return(double("subscription", id: "sub_usage"))
      expect(described_class.ensure_staffing_subscription!(org)).to eq("sub_usage")
      expect(org.reload.staffing_subscription_id).to eq("sub_usage")
    end

    # Stars & Garters got three October bills: three meter jobs at once each
    # made a usage subscription, and each billed the whole month.
    it "takes the usage subscription Stripe already has rather than making another" do
      stripe_subscriptions({ id: "sub_pro", status: "active", created: 1, metadata: {} },
                           { id: "sub_gone", status: "canceled", created: 3, metadata: { kind: "staffing" } },
                           { id: "sub_live", status: "active", created: 2, metadata: { kind: "staffing" } })
      expect(Stripe::Subscription).not_to receive(:create)
      expect(described_class.ensure_staffing_subscription!(org)).to eq("sub_live")
      expect(org.reload.staffing_subscription_id).to eq("sub_live")
    end

    it "makes none when another job got there first: it looks again under the lock" do
      stripe_subscriptions
      stale = Organization.find(org.id)
      org.update_column(:staffing_subscription_id, "sub_first")
      expect(Stripe::Subscription).not_to receive(:create)
      expect(described_class.ensure_staffing_subscription!(stale)).to eq("sub_first")
    end
  end

  describe ".resubscribe_calendar_month!" do
    it "cancels the old usage subscription without a bill and starts one that bills on the 1st" do
      org.update!(staffing_subscription_id: "sub_old")
      allow(SubscriptionPlan).to receive(:staffing_subscription_items).and_return([ { price: "price_staff" } ])
      expect(Stripe::Subscription).to receive(:cancel).with("sub_old")
      allow(Stripe::Subscription).to receive(:list).and_return(Stripe::ListObject.construct_from(data: [ { id: "sub_old", status: "canceled", created: 1, metadata: { kind: "staffing" } } ]))
      expect(Stripe::Subscription).to receive(:create).with(hash_including(billing_cycle_anchor_config: { day_of_month: 1 }), anything)
                                                      .and_return(double("subscription", id: "sub_cal"))
      expect(described_class.resubscribe_calendar_month!(org)).to eq("sub_cal")
      expect(org.reload.staffing_subscription_id).to eq("sub_cal")
    end
  end
end
