# frozen_string_literal: true

require "rails_helper"

# The Messages count is one number in both modes (the one inbox, V1.1 plan
# §0a; MessagesInbox): every unread thread this person is subscribed to,
# whichever organization or hat it's under. The badge must always equal what
# the list shows as unread, and mark-all-read must bring it to zero.
RSpec.describe "Messages count invariants", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:org_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  def sign_in
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  # The core invariant: the badge equals the one inbox's unread rows.
  def expect_badge_to_match_list!
    list_unread = Message.inbox_for(owner).where(id: owner.message_subscriptions.unread.select(:message_id)).count
    badge = owner.unread_message_count
    expect(badge).to eq(list_unread), "badge=#{badge} but list_unread=#{list_unread}"
  end

  before { sign_in }

  describe "GET /manage/messages" do
    it "renders and badge == list-unread == 0 when there are no messages" do
      get manage_messages_path
      expect(response).to have_http_status(:ok)
      expect(owner.unread_message_count).to eq(0)
      expect_badge_to_match_list!
    end

    it "counts a normal production-visible unread thread" do
      msg = create(:message, :production_visible, organization: org, production: production, sender: owner)
      create(:message_subscription, user: owner, message: msg, unread_count: 1)

      get manage_messages_path
      expect(response).to have_http_status(:ok)
      expect(owner.unread_message_count).to eq(1)
      expect_badge_to_match_list!
    end

    it "counts an unread thread from another organization too, and lists it with that organization's pill" do
      other_org = create(:organization, name: "Moonlight Players")
      create(:organization_role, :manager, user: owner, organization: other_org)
      other_prod = create(:production, organization: other_org)
      other_msg = create(:message, :production_visible, organization: other_org, production: other_prod, sender: owner, subject: "Moonlight call time")
      create(:message_subscription, user: owner, message: other_msg, unread_count: 1)

      post set_organization_path(id: org.id) # two organizations now: say which one production mode is in
      get manage_messages_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Moonlight call time")
      row = Nokogiri::HTML(response.body).at_css("a[data-message-id='#{other_msg.id}']")
      expect(row.at_css("[data-inbox-pill]").text.squish).to eq("Moonlight Players")
      expect(row["data-switch"]).to eq("true")
      expect(owner.unread_message_count).to eq(1)
      expect_badge_to_match_list!
    end
  end

  describe "POST /manage/messages/mark_all_read" do
    it "zeroes the badge: one inbox, so every subscription is read now" do
      visible = create(:message, :production_visible, organization: org, production: production, sender: owner)
      visible_sub = create(:message_subscription, user: owner, message: visible, unread_count: 2)
      sys = create(:message, organization: org, production: production, visibility: :personal, message_type: :system, system_generated: true, sender: nil)
      sys_sub = create(:message_subscription, user: owner, message: sys, unread_count: 1)

      post mark_all_read_manage_messages_path

      expect(visible_sub.reload.unread_count).to eq(0)
      expect(sys_sub.reload.unread_count).to eq(0)
      expect(owner.unread_message_count).to eq(0)
      expect_badge_to_match_list!
    end
  end

  describe "POST /manage/messages/:id/mark_unread" do
    it "flips a read thread back to unread (subscription + recipient) and restores the badge" do
      msg = create(:message, :production_visible, organization: org, production: production, sender: owner)
      sub = create(:message_subscription, user: owner, message: msg, unread_count: 0, last_read_at: 1.hour.ago)
      # Make owner a recipient too, with read_at set, to verify the recipient flip.
      owner_person = create(:person, user: owner, email: owner.email_address)
      mr = create(:message_recipient, message: msg, recipient: owner_person, read_at: 1.hour.ago)

      post mark_unread_manage_message_path(msg)

      expect(sub.reload.unread_count).to be >= 1
      expect(sub.last_read_at).to be_nil
      expect(mr.reload.read_at).to be_nil
      expect(owner.unread_message_count).to eq(1)
      expect_badge_to_match_list!
    end

    it "is a graceful no-op when the user has no subscription to the thread" do
      msg = create(:message, :production_visible, organization: org, production: production, sender: owner)
      # No subscription created.
      expect {
        post mark_unread_manage_message_path(msg)
      }.not_to raise_error
      expect(owner.unread_message_count).to eq(0)
      expect_badge_to_match_list!
    end
  end
end
