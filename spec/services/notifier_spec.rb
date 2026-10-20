# frozen_string_literal: true

require "rails_helper"

# Notifications, separate from Messages (V1.1 plan §9): the record, the push
# by each person's switch, and Ticketing's notices reaching managers' lists.
RSpec.describe Notifier do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, email_address: "owner@sg.example") }
  let(:manager) { create(:user, email_address: "manager@sg.example") }
  let(:org) { create(:organization, :pro, name: "Stars & Garters", owner: owner, stripe_account_id: "acct_sg", payouts_enabled: true) }

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    TicketingProfile.for(org).update!(enabled: true, slug: "starsandgarters")
  end

  it "records the notification with the template's words and a local path" do
    n = described_class.deliver(user: manager, category: "ticketing_milestones", kind: "sold_out", template_key: "ticketing_sold_out",
                                variables: { what: "General", show_title: "Comedy Night", show_date: "Fri, Oct 23" },
                                path: "https://cocoscout.com/manage/ticketing/shows/5?tab=orders", organization: org)
    expect(n.title).to eq("Sold out: General, Comedy Night on Fri, Oct 23")
    expect(n.path).to eq("/manage/ticketing/shows/5?tab=orders")
    expect(n).to be_production_mode
    expect(manager.unread_notification_count).to eq(1)
  end

  it "pushes only when the person's switch for its group is on" do
    manager.device_tokens.create!(token: "tok", platform: "ios")
    expect {
      described_class.deliver(user: manager, category: "ticketing_milestones", kind: "sold_out", template_key: "ticketing_sold_out", variables: { what: "x", show_title: "y", show_date: "z" })
    }.to have_enqueued_job(PushDeliveryJob)

    manager.set_notification_switches(push: { "ticketing_milestones" => "0" })
    manager.save!
    expect {
      described_class.deliver(user: manager, category: "ticketing_milestones", kind: "sold_out", template_key: "ticketing_sold_out", variables: { what: "x", show_title: "y", show_date: "z" })
    }.not_to have_enqueued_job(PushDeliveryJob)
    expect(manager.notifications.count).to eq(2)
  end

  describe "Ticketing's notices" do
    it "reach each manager whose plan emails it, or whose push for its group is on" do
      # Reports: the usual plan emails them; push is off by default.
      TicketingNotifier.deliver(org, "daily_summary", { "date_label" => "Monday", "tickets_sold" => "3", "ticket_sales" => "$60" })
      expect(owner.notifications.pluck(:kind)).to eq([ "daily_summary" ])
      expect(manager.notifications.pluck(:category)).to eq([ "ticketing_reports" ])

      # Each sale: the usual plan doesn't email it, but push is on by default.
      TicketingNotifier.deliver(org, "sale", { "ticket_count" => "2 tickets", "show_title" => "Comedy Night", "show_date" => "Fri" })
      expect(manager.notifications.where(kind: "sale").count).to eq(1)

      manager.set_notification_switches(push: { "ticketing_sales" => "0" })
      manager.save!
      TicketingNotifier.deliver(org, "sale", { "ticket_count" => "1 ticket", "show_title" => "Comedy Night", "show_date" => "Fri" })
      expect(manager.notifications.where(kind: "sale").count).to eq(1)
      expect(owner.notifications.where(kind: "sale").count).to eq(2)
    end
  end

  describe "the person's switches" do
    it "keep the older email keys in step, so today's emails still honor them" do
      manager.set_notification_switches(email: { "casting" => "0", "signups" => "1" })
      manager.save!
      expect(manager.notification_enabled?(:vacancy_invitations)).to be(false)
      expect(manager.notification_enabled?(:vacancy_notifications)).to be(false)
      expect(manager.notification_email?("casting")).to be(false)
      expect(manager.notification_email?("signups")).to be(true)
    end

    it "never lets a person set email that is the organization's by plan" do
      manager.set_notification_switches(email: { "ticketing_sales" => "1" })
      expect(manager.notification_email?("ticketing_sales")).to be(false)
    end

    it "lets message pushes be switched off" do
      expect(manager.message_push?).to be(true)
      manager.set_notification_switches(push: { "messages" => "0" })
      expect(manager.message_push?).to be(false)
    end
  end

  describe "ContentTemplateService.deliver with notification:" do
    let(:payee) { create(:person, name: "Sam Staffer", user: create(:user)) }
    let(:no_account) { create(:person, name: "Pat Nobody") }

    before do
      ContentTemplate.find_or_create_by!(key: "payout_returned_to_payee") do |t|
        t.name = "Payout returned"; t.channel = "both"; t.category = "payouts"
        t.subject = "Your {{amount}} from {{organization_name}} came back"; t.body = "Hi {{recipient_name}}"
      end
    end

    def deliver(gate:)
      ContentTemplateService.deliver(template_key: "payout_returned_to_payee", variables: { recipient_name: "Sam", organization_name: "Stars & Garters", amount: "$50.00" },
                                     sender: nil, recipients: [ payee, no_account ], organization: org,
                                     notification: { category: "pay", kind: "payout_returned", path: "/my/payments/setup", gate_email: gate })
    end

    it "notifies people with an account instead of messaging them, and emails everyone" do
      result = nil
      expect { result = deliver(gate: true) }.to change(Notification, :count).by(1).and(not_change(Message, :count))
      expect(result[:emails_queued]).to eq(2)
      rendered = ContentTemplateService.render("payout_returned_to_payee", { recipient_name: "Sam", organization_name: "Stars & Garters", amount: "$50.00" })
      expect(payee.user.notifications.last.title).to eq(rendered[:push_body].presence || rendered[:subject])
    end

    it "leaves out the email of someone who switched it off, never someone without an account" do
      payee.user.set_notification_switches(email: { "pay" => "0" })
      payee.user.save!
      expect(deliver(gate: true)[:emails_queued]).to eq(1)
      expect(deliver(gate: false)[:emails_queued]).to eq(2)
    end
  end
end
