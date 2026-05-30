# frozen_string_literal: true

require "rails_helper"

# The contract this file pins down: the manage sidebar badge **must equal** the
# number of unread threads a user can actually open from the manage messages
# list, for any combination of message types and orgs. (Before the fix the
# badge counted every subscription to any org message, so system-generated
# notifications + cross-scope threads kept it pinned above zero even after the
# visible list was empty.)
RSpec.describe "Manage messages count invariants", type: :request do
  let(:password) { "Password123!" }
  let(:owner) { create(:user, password: password) }
  let!(:org) { create(:organization, owner: owner) }
  let!(:org_role) { create(:organization_role, :manager, user: owner, organization: org) }
  let!(:production) { create(:production, organization: org) }

  def sign_in
    post handle_signin_path, params: { email_address: owner.email_address, password: password }
  end

  # Manage inbox + badge helpers read `Current.organization` via
  # `accessible_productions`. The controller always has it set; in specs we set
  # it explicitly around the assertion so we exercise the same code path.
  def with_current_org
    prev = Current.organization
    Current.organization = org
    yield
  ensure
    Current.organization = prev
  end

  # The core invariant.
  def expect_badge_to_match_list!
    with_current_org do
      list_unread = Message.manage_inbox_for(owner, org)
                           .where(id: owner.message_subscriptions.unread.select(:message_id))
                           .count
      badge = owner.unread_message_count_for_org(org)
      expect(badge).to eq(list_unread),
                       "badge=#{badge} but list_unread=#{list_unread}"
    end
  end

  before { sign_in }

  describe "GET /manage/messages" do
    it "renders and badge == list-unread == 0 when there are no messages" do
      get manage_messages_path
      expect(response).to have_http_status(:ok)
      with_current_org { expect(owner.unread_message_count_for_org(org)).to eq(0) }
      expect_badge_to_match_list!
    end

    it "counts a normal production-visible unread thread" do
      msg = create(:message, :production_visible, organization: org, production: production, sender: owner)
      create(:message_subscription, user: owner, message: msg, unread_count: 1)

      get manage_messages_path
      expect(response).to have_http_status(:ok)
      with_current_org { expect(owner.unread_message_count_for_org(org)).to eq(1) }
      expect_badge_to_match_list!
    end

    it "does NOT count a system-generated thread (the precise regression that pinned the old badge above zero)" do
      sys = create(:message,
                   organization: org, production: production,
                   visibility: :personal,
                   message_type: :system, system_generated: true,
                   sender: nil)
      create(:message_subscription, user: owner, message: sys, unread_count: 1)

      get manage_messages_path
      expect(response).to have_http_status(:ok)
      with_current_org { expect(owner.unread_message_count_for_org(org)).to eq(0) }
      expect_badge_to_match_list!
    end

    it "does NOT leak unread from another organization into this badge" do
      other_org = create(:organization)
      other_prod = create(:production, organization: other_org)
      other_msg = create(:message, :production_visible, organization: other_org, production: other_prod, sender: owner)
      create(:message_subscription, user: owner, message: other_msg, unread_count: 1)

      get manage_messages_path
      expect(response).to have_http_status(:ok)
      with_current_org { expect(owner.unread_message_count_for_org(org)).to eq(0) }
      expect_badge_to_match_list!
    end
  end

  describe "POST /manage/messages/mark_all_read" do
    it "zeroes the badge and only touches inbox subscriptions (system-generated unaffected)" do
      visible = create(:message, :production_visible, organization: org, production: production, sender: owner)
      visible_sub = create(:message_subscription, user: owner, message: visible, unread_count: 2)
      sys = create(:message,
                   organization: org, production: production,
                   visibility: :personal,
                   message_type: :system, system_generated: true,
                   sender: nil)
      sys_sub = create(:message_subscription, user: owner, message: sys, unread_count: 1)

      post mark_all_read_manage_messages_path

      expect(visible_sub.reload.unread_count).to eq(0)
      # The system-generated subscription is outside the manage inbox, so
      # mark-all-read leaves it alone — it can't be "stuck" because it never
      # contributes to the badge in the first place.
      expect(sys_sub.reload.unread_count).to eq(1)
      with_current_org { expect(owner.unread_message_count_for_org(org)).to eq(0) }
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
      with_current_org { expect(owner.unread_message_count_for_org(org)).to eq(1) }
      expect_badge_to_match_list!
    end

    it "is a graceful no-op when the user has no subscription to the thread" do
      msg = create(:message, :production_visible, organization: org, production: production, sender: owner)
      # No subscription created.
      expect {
        post mark_unread_manage_message_path(msg)
      }.not_to raise_error
      with_current_org { expect(owner.unread_message_count_for_org(org)).to eq(0) }
      expect_badge_to_match_list!
    end
  end
end
