# frozen_string_literal: true

require "rails_helper"

# Superadmin Finances, Email (Tim, 2026-11-17): how much mail CocoScout has
# sent against its Mailgun plan, the extra follower emails organizations
# bought, and the notices to superadmins about both.
RSpec.describe "Superadmin Finances - Email", type: :request do
  include ActiveJob::TestHelper

  let(:password) { "Password123!" }
  let!(:superadmin_user) { create(:user, email_address: User::SUPERADMIN_EMAILS.first, password: password) }
  let!(:owner) { create(:user, password: password) }
  let!(:organization) { create(:organization, :pro, owner: owner, name: "The Holly Problem") }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  describe "counting" do
    it "counts every email as it goes out, one for each person it's sent to" do
      expect { MailVolume.count!(3) }.to change { MailVolume.new.sent }.by(3)
      expect { MailVolume.count!(2) }.to change { MailVolume.new.sent }.by(2)
      expect(MailVolumeMonth.count).to eq(1)

      mail = ActionMailer::Base.mail(from: "info@cocoscout.com", to: [ "a@example.com", "b@example.com" ], subject: "Hi", body: "Hello")
      expect { MailVolumeObserver.delivered_email(mail) }.to change { MailVolume.new.sent }.by(2)
    end

    it "keeps the plan's size as a setting" do
      expect(MailVolume.plan_emails).to eq(10_000)
      MailVolume.set!(plan_emails: 50_000, upgrade_at: 110_000)
      expect(MailVolume.new).to have_attributes(plan_emails: 50_000, upgrade_at: 110_000)
    end
  end

  describe "notices" do
    it "notifies superadmins once when the month gets close to the plan" do
      MailVolume.count!(7_900)
      expect { MailVolume.check! }.not_to change(superadmin_user.notifications, :count)

      MailVolume.count!(200)
      expect { MailVolume.check! }.to change(superadmin_user.notifications, :count).by(1)
      expect(superadmin_user.notifications.last.title).to eq("CocoScout has sent 8,100 of the 10,000 emails in this month's Mailgun plan")
      expect { MailVolume.check! }.not_to change(superadmin_user.notifications, :count)
    end

    it "says when the month's pace means it's time to move up a plan, and not in a month's first days" do
      travel_to(Date.current.beginning_of_month + 2.days + 12.hours) do
        MailVolume.count!(6_000)
        expect(MailVolume.new.projected).to be_nil
      end
      travel_to(Date.current.beginning_of_month + 9.days + 12.hours) do
        MailVolume.count!(2_000)
        volume = MailVolume.new
        expect(volume.projected).to be > 21_000
        expect { MailVolume.check! }.to change { superadmin_user.notifications.where(kind: "mail_upgrade_near").count }.by(1)
      end
    end

    it "notifies superadmins when an organization buys a block" do
      expect { organization.follower_email_blocks.create!(bought_by: owner) }.to change(superadmin_user.notifications, :count).by(1)
      expect(superadmin_user.notifications.last.title).to eq("The Holly Problem bought 1,000 extra emails to followers for $3")
    end
  end

  describe "the page" do
    it "shows the month against the plan, the blocks bought and who holds paid emails, to superadmins only" do
      MailVolume.count!(1_234)
      organization.follower_email_blocks.create!(bought_by: owner)

      sign_in(superadmin_user)
      get finances_email_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1,234 of 10,000").and include("Extra follower emails bought").and include("The Holly Problem")
        .and include("Who still holds paid emails")

      patch finances_email_path, params: { plan_emails: "50000", upgrade_at: "110000" }
      expect(MailVolume.plan_emails).to eq(50_000)

      get signout_path
      sign_in(owner)
      get finances_email_path
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "the send window" do
    let(:list) { MailingList.main_for!(organization) }

    before do
      create(:organization_role, :manager, user: owner, organization: organization)
      now = Time.current
      rows = 620.times.map { |i| { organization_id: organization.id, email: "f#{i}@example.com", status: "subscribed", unsubscribe_token: SecureRandom.hex(12), created_at: now, updated_at: now } }
      ids = Follower.insert_all(rows, returning: %w[id]).rows.flatten
      MailingListMembership.insert_all(ids.map { |id| { mailing_list_id: list.id, follower_id: id, created_at: now, updated_at: now } })
      sign_in(owner)
      post set_organization_path(id: organization.id)
    end

    # Dev walk, 2026-11-17: with nothing counted yet the page blamed "a month's first few days" on the 17th.
    it "says why there is no pace yet: nothing counted, counting only just begun, or the month only just begun" do
      sign_in(superadmin_user)
      travel_to(Date.current.beginning_of_month + 16.days + 12.hours) do
        get finances_email_path
        expect(response.body).to include("Nothing has been counted yet this month.", "There is nothing to work a pace out from yet.")
        expect(response.body).not_to include("first few days")

        MailVolume.count!(40)
        get finances_email_path
        expect(response.body).to include("Counting began on #{Time.current.strftime('%b %-d')}. A pace means little until it has run for 5 days.")
      end
      MailVolumeMonth.delete_all
      travel_to(Date.current.next_month.beginning_of_month + 1.day + 12.hours) do
        MailVolumeMonth.create!(month: Date.current.beginning_of_month, sent: 40, counted_from: Date.current.beginning_of_month.beginning_of_day)
        get finances_email_path
        expect(response.body).to include("A month's pace means little in its first few days.")
      end
    end

    it "offers a block when an email goes past what's left, and buys it only on that button" do
      email = organization.follower_emails.create!(subject: "News", body: "<p>Hello</p>", status: "draft", created_by: owner,
                                                   targets: { "list_ids" => [ list.id ], "segment_ids" => [] })
      get manage_edit_follower_email_path(email, review: 1)
      expect(response.body).to include("This email goes to 620 followers").and include("Add 1,000 for $3 and send")
        .and include("It goes on your next bill")

      post manage_follower_email_deliver_path(email)
      expect(email.reload.status).to eq("draft")
      expect(organization.follower_email_blocks).to be_empty

      post manage_follower_email_deliver_path(email), params: { buy_blocks: 1 }
      expect(email.reload).to have_attributes(status: "sending", paid_emails_used: 120)
      expect(organization.follower_email_blocks.count).to eq(1)
    end
  end
end
