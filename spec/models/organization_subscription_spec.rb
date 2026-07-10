# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organization, "subscription & entitlements", type: :model do
  let(:organization) { create(:organization) }

  describe "#on_paid_plan?" do
    it "is false for a brand-new free org" do
      expect(organization.on_paid_plan?).to be false
    end

    it "is true when comped indefinitely" do
      organization.update!(comped_indefinitely: true)
      expect(organization.on_paid_plan?).to be true
    end

    it "is true when comped until a future date, false once it passes" do
      organization.update!(comped_until: 1.month.from_now)
      expect(organization.on_paid_plan?).to be true

      organization.update!(comped_until: 1.day.ago)
      expect(organization.on_paid_plan?).to be false
    end

    it "is true for an active/trialing/past_due Stripe status" do
      %w[active trialing past_due].each do |status|
        organization.update!(subscription_status: status)
        expect(organization.on_paid_plan?).to be(true), "expected #{status} to grant access"
      end
    end

    it "is false for canceled/incomplete Stripe status" do
      %w[canceled incomplete].each do |status|
        organization.update!(subscription_status: status)
        expect(organization.on_paid_plan?).to be(false), "expected #{status} to deny access"
      end
    end
  end

  describe "#feature_available?" do
    it "always allows Producer-plan features regardless of plan" do
      %i[messages casting shows contacts documents].each do |feature|
        expect(organization.feature_available?(feature)).to be true
      end
    end

    it "gates paid features behind a paid plan" do
      Organization::PAID_FEATURES.each do |feature|
        expect(organization.feature_available?(feature)).to be false
      end

      organization.update!(comped_indefinitely: true)
      Organization::PAID_FEATURES.each do |feature|
        expect(organization.feature_available?(feature)).to be true
      end
    end
  end

  describe "#at_event_limit? / #events_in_month" do
    let(:production) { create(:production, organization: organization) }

    it "counts non-canceled events in the month and blocks at the limit" do
      limit = Organization::FREE_MONTHLY_EVENT_LIMIT
      base = Time.zone.now.beginning_of_month + 10.days

      (limit - 1).times { |i| create(:show, production: production, date_and_time: base + i.hours) }
      expect(organization.at_event_limit?(base)).to be false

      create(:show, production: production, date_and_time: base + limit.hours)
      expect(organization.events_in_month(base).count).to eq(limit)
      expect(organization.at_event_limit?(base)).to be true
    end

    it "ignores canceled events" do
      base = Time.zone.now.beginning_of_month + 10.days
      Organization::FREE_MONTHLY_EVENT_LIMIT.times { |i| create(:show, production: production, date_and_time: base + i.hours) }
      create(:show, production: production, date_and_time: base + 100.hours, canceled: true)

      expect(organization.events_in_month(base).count).to eq(Organization::FREE_MONTHLY_EVENT_LIMIT)
    end

    it "never limits a paid org" do
      organization.update!(comped_indefinitely: true)
      base = Time.zone.now.beginning_of_month + 10.days
      (Organization::FREE_MONTHLY_EVENT_LIMIT + 3).times { |i| create(:show, production: production, date_and_time: base + i.hours) }

      expect(organization.at_event_limit?(base)).to be false
    end
  end

  describe "#at_production_limit?" do
    it "is reached after one active schedulable production on the Producer plan" do
      expect(organization.at_production_limit?).to be false
      create(:production, organization: organization)
      expect(organization.at_production_limit?).to be true
    end

    it "ignores courses and archived productions" do
      create(:production, organization: organization, production_type: "course")
      create(:production, organization: organization, archived_at: Time.current)
      expect(organization.at_production_limit?).to be false
    end

    it "never limits a paid org" do
      organization.update!(comped_indefinitely: true)
      3.times { create(:production, organization: organization) }
      expect(organization.at_production_limit?).to be false
    end
  end
end
