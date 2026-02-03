# frozen_string_literal: true

require "rails_helper"

RSpec.describe Message do
  describe "associations" do
    let(:message) { create(:message) }

    it "belongs to sender" do
      expect(message).to respond_to(:sender)
      expect(message.sender).to be_present
    end

    it "belongs to organization (optional)" do
      expect(message).to respond_to(:organization)
    end

    it "belongs to production (optional)" do
      expect(message).to respond_to(:production)
    end

    it "belongs to show (optional)" do
      expect(message).to respond_to(:show)
    end

    it "belongs to parent_message (optional)" do
      expect(message).to respond_to(:parent_message)
    end

    it "has many child_messages" do
      expect(message).to respond_to(:child_messages)
    end

    it "has many message_recipients" do
      expect(message).to respond_to(:message_recipients)
    end

    it "has many message_subscriptions" do
      expect(message).to respond_to(:message_subscriptions)
    end

    it "has many message_reactions" do
      expect(message).to respond_to(:message_reactions)
    end

    it "has many message_regards" do
      expect(message).to respond_to(:message_regards)
    end
  end

  describe "validations" do
    it "requires a subject" do
      message = build(:message, subject: nil)
      expect(message).not_to be_valid
      expect(message.errors[:subject]).to be_present
    end

    it "validates subject length" do
      message = build(:message, subject: "a" * 256)
      expect(message).not_to be_valid
      expect(message.errors[:subject]).to be_present
    end

    it "requires a message_type" do
      message = build(:message, message_type: nil)
      expect(message).not_to be_valid
      expect(message.errors[:message_type]).to be_present
    end
  end

  describe "enums" do
    it "defines visibility enum" do
      expect(Message.visibilities.keys).to contain_exactly("personal", "production", "show")
    end

    it "defines message_type enum" do
      expect(Message.message_types.keys).to contain_exactly(
        "cast_contact", "talent_pool", "direct", "production_contact", "system"
      )
    end
  end

  describe "scopes" do
    let!(:root_message) { create(:message) }
    let!(:reply) { create(:message, parent_message: root_message) }
    let!(:deleted_message) { create(:message, :deleted) }

    describe ".root_messages" do
      it "returns only messages without parent" do
        expect(Message.root_messages).to include(root_message, deleted_message)
        expect(Message.root_messages).not_to include(reply)
      end
    end

    describe ".not_deleted" do
      it "excludes soft-deleted messages" do
        expect(Message.not_deleted).to include(root_message, reply)
        expect(Message.not_deleted).not_to include(deleted_message)
      end
    end
  end

  describe "#deleted?" do
    it "returns true when deleted_at is set" do
      message = build(:message, deleted_at: Time.current)
      expect(message.deleted?).to be true
    end

    it "returns false when deleted_at is nil" do
      message = build(:message, deleted_at: nil)
      expect(message.deleted?).to be false
    end
  end

  describe "#soft_delete!" do
    it "sets deleted_at timestamp" do
      message = create(:message)
      expect { message.soft_delete! }.to change { message.deleted_at }.from(nil)
    end
  end

  describe "#smart_delete!" do
    context "when message has children" do
      it "soft deletes" do
        parent = create(:message)
        create(:message, parent_message: parent)

        parent.smart_delete!
        expect(parent.deleted?).to be true
        expect(Message.exists?(parent.id)).to be true
      end
    end

    context "when message has no children" do
      it "hard deletes" do
        message = create(:message)
        message.smart_delete!
        expect(Message.exists?(message.id)).to be false
      end
    end
  end

  describe "#can_be_deleted_by?" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    it "returns true when user is the sender" do
      message = create(:message, sender: user)
      expect(message.can_be_deleted_by?(user)).to be true
    end

    it "returns false when user is not the sender" do
      message = create(:message, sender: other_user)
      expect(message.can_be_deleted_by?(user)).to be false
    end

    it "returns false when user is nil" do
      message = create(:message)
      expect(message.can_be_deleted_by?(nil)).to be false
    end
  end

  describe "#reply?" do
    it "returns true when message has parent" do
      parent = create(:message)
      reply = create(:message, parent_message: parent)
      expect(reply.reply?).to be true
    end

    it "returns false when message has no parent" do
      message = create(:message)
      expect(message.reply?).to be false
    end
  end

  describe "#thread_depth" do
    it "returns 0 for root message" do
      message = create(:message)
      expect(message.thread_depth).to eq(0)
    end

    it "returns 1 for direct reply" do
      parent = create(:message)
      reply = create(:message, parent_message: parent)
      expect(reply.thread_depth).to eq(1)
    end

    it "returns correct depth for nested replies" do
      root = create(:message)
      level1 = create(:message, parent_message: root)
      level2 = create(:message, parent_message: level1)
      level3 = create(:message, parent_message: level2)

      expect(level3.thread_depth).to eq(3)
    end
  end

  describe "#root_message" do
    it "returns self for root message" do
      message = create(:message)
      expect(message.root_message).to eq(message)
    end

    it "returns the root for nested replies" do
      root = create(:message)
      level1 = create(:message, parent_message: root)
      level2 = create(:message, parent_message: level1)

      expect(level2.root_message).to eq(root)
    end
  end

  describe "#sender_name" do
    it "returns user's person name when sender is a user" do
      user = create(:user)
      person = create(:person, user: user, name: "John Doe")
      user.update!(default_person: person)
      message = create(:message, sender: user)

      expect(message.sender_name).to eq("John Doe")
    end

    it "returns person name when sender is a person" do
      person = create(:person, name: "Jane Smith")
      message = build(:message)
      message.sender = person
      message.save!

      expect(message.sender_name).to eq("Jane Smith")
    end
  end

  describe "recipient methods" do
    let(:sender) { create(:user) }
    let(:recipient_user) { create(:user) }
    let(:recipient_person) { create(:person, user: recipient_user) }
    let(:message) { create(:message, sender: sender) }

    before do
      message.message_recipients.create!(recipient: recipient_person)
    end

    describe "#recipient?" do
      it "returns true for a recipient" do
        expect(message.recipient?(recipient_person)).to be true
      end

      it "returns false for non-recipient" do
        other_person = create(:person)
        expect(message.recipient?(other_person)).to be false
      end
    end

    describe "#recipient_count" do
      it "returns the number of recipients" do
        expect(message.recipient_count).to eq(1)
      end
    end

    describe "#recipient_names" do
      it "returns array of recipient names" do
        expect(message.recipient_names).to include(recipient_person.name)
      end
    end
  end

  describe "read/archive methods" do
    let(:sender) { create(:user) }
    let(:recipient_user) { create(:user) }
    let(:recipient_person) { create(:person, user: recipient_user) }
    let(:message) { create(:message, sender: sender) }
    let!(:message_recipient) { message.message_recipients.create!(recipient: recipient_person) }

    describe "#unread_for?" do
      it "returns true when message is unread" do
        expect(message.unread_for?(recipient_person)).to be true
      end

      it "returns false when message is read" do
        message_recipient.update!(read_at: Time.current)
        expect(message.unread_for?(recipient_person)).to be false
      end
    end

    describe "#mark_read_for!" do
      it "marks message as read for recipient" do
        message.mark_read_for!(recipient_person)
        expect(message.unread_for?(recipient_person)).to be false
      end
    end

    describe "#archive_for!" do
      it "archives message for recipient" do
        message.archive_for!(recipient_person)
        expect(message_recipient.reload.archived_at).to be_present
      end
    end
  end

  describe "reaction methods" do
    let(:user) { create(:user) }
    let(:message) { create(:message, sender: user) }

    describe "#add_reaction!" do
      it "creates a new reaction" do
        expect {
          message.add_reaction!(user, "like")
        }.to change { message.message_reactions.count }.by(1)
      end

      it "does not duplicate reactions" do
        message.add_reaction!(user, "like")
        expect {
          message.add_reaction!(user, "like")
        }.not_to change { message.message_reactions.count }
      end
    end

    describe "#remove_reaction!" do
      it "removes the reaction" do
        message.add_reaction!(user, "like")
        expect {
          message.remove_reaction!(user, "like")
        }.to change { message.message_reactions.count }.by(-1)
      end
    end

    describe "#toggle_reaction!" do
      it "adds reaction when none exists" do
        expect(message.toggle_reaction!(user, "like")).to be true
        expect(message.user_reaction(user)).to eq("like")
      end

      it "removes same reaction" do
        message.add_reaction!(user, "like")
        expect(message.toggle_reaction!(user, "like")).to be false
        expect(message.user_reaction(user)).to be_nil
      end

      it "replaces different reaction" do
        message.add_reaction!(user, "like")
        expect(message.toggle_reaction!(user, "love")).to be true
        expect(message.user_reaction(user)).to eq("love")
      end
    end

    describe "#reaction_counts" do
      it "returns counts by emoji" do
        user2 = create(:user)
        message.add_reaction!(user, "like")
        message.add_reaction!(user2, "like")

        expect(message.reaction_counts["like"]).to eq(2)
      end
    end
  end

  describe "subscription methods" do
    let(:user) { create(:user) }
    let(:message) { create(:message) }

    describe "#subscribe!" do
      it "creates a subscription" do
        expect {
          message.subscribe!(user)
        }.to change { MessageSubscription.count }.by(1)
      end

      it "does not duplicate subscriptions" do
        message.subscribe!(user)
        expect {
          message.subscribe!(user)
        }.not_to change { MessageSubscription.count }
      end

      it "can mark as read when subscribing" do
        subscription = message.subscribe!(user, mark_read: true)
        expect(subscription.last_read_at).to be_present
      end
    end

    describe "#subscribed?" do
      it "returns true when subscribed" do
        message.subscribe!(user)
        expect(message.subscribed?(user)).to be true
      end

      it "returns false when not subscribed" do
        expect(message.subscribed?(user)).to be false
      end
    end

    describe "#unsubscribe!" do
      it "removes the subscription" do
        message.subscribe!(user)
        message.unsubscribe!(user)
        expect(message.subscribed?(user)).to be false
      end
    end
  end

  describe "#add_regards" do
    let(:message) { create(:message) }
    let(:production) { create(:production) }
    let(:show) { create(:show) }

    it "adds regardable objects" do
      message.add_regards(production, show)
      expect(message.regardables).to contain_exactly(production, show)
    end

    it "does not duplicate regards" do
      message.add_regards(production)
      message.add_regards(production)
      expect(message.message_regards.count).to eq(1)
    end
  end

  describe "thread methods" do
    let!(:root) { create(:message) }
    let!(:reply1) { create(:message, parent_message: root) }
    let!(:reply2) { create(:message, parent_message: reply1) }

    describe "#descendant_ids" do
      it "returns all descendant message ids" do
        expect(root.descendant_ids).to contain_exactly(reply1.id, reply2.id)
      end

      it "returns empty array for leaf messages" do
        expect(reply2.descendant_ids).to be_empty
      end
    end

    describe "#thread_messages" do
      it "returns all messages in thread" do
        expect(root.thread_messages).to contain_exactly(root, reply1, reply2)
      end
    end
  end

  describe "#subscribe_production_team!" do
    let(:production) { create(:production) }
    let(:org_manager) { create(:user) }
    let(:prod_manager) { create(:user) }
    let(:message) { create(:message, production: production, visibility: :production) }

    before do
      create(:organization_role, organization: production.organization, user: org_manager, company_role: :manager)
      create(:production_permission, production: production, user: prod_manager, role: :manager)
    end

    it "subscribes org-level managers" do
      message.subscribe_production_team!
      expect(message.subscribed?(org_manager)).to be true
    end

    it "subscribes production-level managers" do
      message.subscribe_production_team!
      expect(message.subscribed?(prod_manager)).to be true
    end
  end
end
