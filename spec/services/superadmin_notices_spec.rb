# frozen_string_literal: true

require "rails_helper"
require "ostruct"

# Superadmins hear about a new organization and an organization starting to
# pay for Pro (Tim, 2026-11-14), once per upgrade, as a notification only.
RSpec.describe SuperadminNotices do
  let!(:tim) { create(:user, email_address: User::SUPERADMIN_EMAILS.first) }
  let!(:andie) { create(:user, email_address: User::SUPERADMIN_EMAILS.second) }
  let!(:someone) { create(:user) }

  def told(kind)
    Notification.where(category: "platform", kind: kind)
  end

  describe "a new organization" do
    it "tells every superadmin, and nobody else, with the organization in Superadmin as the tap" do
      Person.create!(email: someone.email_address, name: "Jo Producer", user: someone)
      org = Organization.create!(name: "The Holly Problem", owner: someone)

      expect(told("organization_created").pluck(:user_id)).to contain_exactly(tim.id, andie.id)
      notice = tim.notifications.sole
      expect(notice).to have_attributes(title: "New organization: The Holly Problem, made by Jo Producer",
                                        path: "/superadmin/organizations/#{org.id}", subject: org, organization: nil)
      expect(someone.notifications).to be_empty
    end

    it "pushes with CocoScout as the title, never a person, and sends no email" do
      tim.device_tokens.create!(token: "tok", platform: "ios")
      allow(PushNotificationService).to receive(:notify)

      expect { Organization.create!(name: "Stars & Garters", owner: someone) }.not_to have_enqueued_mail

      notice = tim.notifications.sole
      expect(PushNotificationService).to have_received(:notify).with(
        tim, hash_including(title: "CocoScout", body: notice.title,
                            data: hash_including(path: "/notifications/#{notice.id}/open"))
      )
    end

    it "is told once, not again when the organization is saved" do
      org = Organization.create!(name: "Stars & Garters", owner: someone)
      org.update!(name: "Stars and Garters")

      expect(told("organization_created").where(user: tim).count).to eq(1)
    end

    it "never stops the organization being made" do
      allow(Notifier).to receive(:deliver).and_raise(StandardError, "boom")

      expect { Organization.create!(name: "Stars & Garters", owner: someone) }.to change(Organization, :count).by(1)
    end
  end

  describe "Pro through a subscription of its own" do
    let(:org) { Organization.create!(name: "The Holly Problem", owner: someone) }

    def subscription(status:, interval: "year", period_end: 1.year.from_now.to_i, id: "sub_pro")
      item = OpenStruct.new(price: OpenStruct.new(recurring: OpenStruct.new(interval: interval)))
      OpenStruct.new(id: id, customer: "cus_1", status: status, items: OpenStruct.new(data: [ item ]),
                     current_period_end: period_end, canceled_at: nil, metadata: {})
    end

    def sync(sub) = SubscriptionSyncService.new(org, sub).call

    it "tells the superadmins when it becomes active, with its finances page as the tap" do
      sync(subscription(status: "active"))

      expect(told("pro_started").pluck(:user_id)).to contain_exactly(tim.id, andie.id)
      expect(tim.notifications.find_by(kind: "pro_started")).to have_attributes(
        title: "The Holly Problem started Pro, yearly", path: "/superadmin/finances/orgs/#{org.id}", subject: org
      )
    end

    it "tells them once: the success page and the webhook both syncing, and every renewal after, say nothing more" do
      sync(subscription(status: "incomplete"))
      expect(told("pro_started")).to be_empty

      sync(subscription(status: "active"))
      sync(subscription(status: "active"))
      travel_to(1.year.from_now) { sync(subscription(status: "active", period_end: 2.years.from_now.to_i)) }

      expect(told("pro_started").where(user: tim).count).to eq(1)
    end

    it "counts a trial as the start, and the trial turning paid as nothing new" do
      sync(subscription(status: "trialing", interval: "month"))
      expect(tim.notifications.find_by(kind: "pro_started").title).to eq("The Holly Problem started Pro, monthly, on a trial")

      sync(subscription(status: "active", interval: "month"))
      expect(told("pro_started").where(user: tim).count).to eq(1)
    end

    it "says nothing when a past-due subscription recovers" do
      org.update!(subscription_status: "past_due", subscription_tier: "paid", stripe_subscription_id: "sub_pro")
      sync(subscription(status: "active"))

      expect(told("pro_started")).to be_empty
    end

    it "says nothing for an organization already paying on the monthly bill" do
      org.update!(pro_monthly_from: 1.month.ago)
      sync(subscription(status: "active"))

      expect(told("pro_started")).to be_empty
    end

    it "says nothing about the usage subscription" do
      org.update!(staffing_subscription_id: "sub_usage")
      sync(subscription(status: "active", id: "sub_usage"))

      expect(told("pro_started")).to be_empty
    end

    it "tells them again when an organization that left comes back" do
      sync(subscription(status: "active"))
      sync(subscription(status: "canceled"))
      travel_to(2.months.from_now) { sync(subscription(status: "active", id: "sub_pro_2")) }

      expect(told("pro_started").where(user: tim).count).to eq(2)
    end
  end

  describe "Pro on the monthly bill" do
    let(:org) { Organization.create!(name: "The Holly Problem", owner: someone) }

    before { allow(StaffMeterService).to receive(:ensure_staffing_subscription!) }

    it "tells the superadmins once, however many times it is started" do
      org.start_pro_on_monthly_bill!
      org.start_pro_on_monthly_bill!

      expect(told("pro_started").pluck(:user_id)).to contain_exactly(tim.id, andie.id)
      expect(tim.notifications.find_by(kind: "pro_started")).to have_attributes(
        title: "The Holly Problem started Pro on the monthly bill", path: "/superadmin/finances/orgs/#{org.id}"
      )
    end

    it "tells them when a comped organization starts paying" do
      org.update!(comped_until: 2.weeks.from_now)
      org.start_pro_on_monthly_bill!

      expect(told("pro_started").where(user: tim).count).to eq(1)
    end

    it "says nothing when a canceled plan still running out its month is started again" do
      org.update!(pro_monthly_from: 2.months.ago, pro_monthly_until: Time.current.end_of_month)
      org.start_pro_on_monthly_bill!

      expect(told("pro_started")).to be_empty
    end

    it "says nothing for an organization already paying through its own subscription" do
      org.update!(subscription_status: "active", subscription_tier: "paid")
      org.start_pro_on_monthly_bill!

      expect(told("pro_started")).to be_empty
    end

    it "never stops Pro starting" do
      allow(Notifier).to receive(:deliver).and_raise(StandardError, "boom")
      org.start_pro_on_monthly_bill!

      expect(org.reload.pro_on_monthly_bill?).to be(true)
    end
  end
end
