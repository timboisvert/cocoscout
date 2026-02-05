# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessageService do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:show) { create(:show, production: production) }
  let(:sender) { create(:user) }
  let(:sender_person) { create(:person, user: sender) }
  let(:recipient_user) { create(:user) }
  let(:recipient_person) { create(:person, user: recipient_user) }

  before do
    sender.update!(default_person: sender_person)
  end

  describe ".send_direct" do
    it "creates a direct message" do
      message = described_class.send_direct(
        sender: sender,
        recipient_person: recipient_person,
        subject: "Hello",
        body: "How are you?"
      )

      expect(message).to be_persisted
      expect(message.sender).to eq(sender)
      expect(message.subject).to eq("Hello")
      expect(message.visibility).to eq("personal")
      expect(message.message_type).to eq("direct")
    end

    it "creates recipient record" do
      message = described_class.send_direct(
        sender: sender,
        recipient_person: recipient_person,
        subject: "Hello",
        body: "Content"
      )

      expect(message.message_recipients.count).to eq(1)
      expect(message.recipient?(recipient_person)).to be true
    end

    it "subscribes sender and recipient" do
      message = described_class.send_direct(
        sender: sender,
        recipient_person: recipient_person,
        subject: "Hello",
        body: "Content"
      )

      expect(message.subscribed?(sender)).to be true
      expect(message.subscribed?(recipient_user)).to be true
    end

    it "returns nil when recipient has no user account" do
      person_without_user = create(:person, user: nil)

      message = described_class.send_direct(
        sender: sender,
        recipient_person: person_without_user,
        subject: "Hello",
        body: "Content"
      )

      expect(message).to be_nil
    end

    it "can include parent message for threading" do
      parent = create(:message, sender: sender)

      reply = described_class.send_direct(
        sender: sender,
        recipient_person: recipient_person,
        subject: "Re: Hello",
        body: "Reply content",
        parent_message: parent
      )

      expect(reply.parent_message).to eq(parent)
    end
  end

  describe ".send_to_show_cast" do
    let(:role) { create(:role, production: production) }
    let(:cast_person) { create(:person, user: create(:user)) }

    before do
      create(:show_person_role_assignment, show: show, role: role, assignable: cast_person)
    end

    it "creates a show-scoped message" do
      message = described_class.send_to_show_cast(
        show: show,
        sender: sender,
        subject: "Show Update",
        body: "Important information"
      )

      expect(message).to be_persisted
      expect(message.show).to eq(show)
      expect(message.visibility).to eq("show")
      expect(message.message_type).to eq("cast_contact")
    end

    it "includes cast members as recipients" do
      message = described_class.send_to_show_cast(
        show: show,
        sender: sender,
        subject: "Show Update",
        body: "Content"
      )

      expect(message.recipient?(cast_person)).to be true
    end
  end

  describe ".send_to_production_cast" do
    let(:role) { create(:role, production: production) }
    let(:cast_person) { create(:person, user: create(:user)) }

    before do
      create(:show_person_role_assignment, show: show, role: role, assignable: cast_person)
    end

    it "creates a production-scoped message" do
      message = described_class.send_to_production_cast(
        production: production,
        sender: sender,
        subject: "Production Update",
        body: "Important information"
      )

      expect(message).to be_persisted
      expect(message.production).to eq(production)
      expect(message.visibility).to eq("production")
      expect(message.message_type).to eq("cast_contact")
    end

    it "includes cast members as recipients" do
      message = described_class.send_to_production_cast(
        production: production,
        sender: sender,
        subject: "Production Update",
        body: "Content"
      )

      expect(message.recipient?(cast_person)).to be true
    end
  end

  describe ".send_to_talent_pool" do
    let(:talent_pool) { production.talent_pool }
    let(:pool_person1) { create(:person, user: create(:user)) }
    let(:pool_person2) { create(:person, user: create(:user)) }

    before do
      create(:talent_pool_membership, talent_pool: talent_pool, member: pool_person1)
      create(:talent_pool_membership, talent_pool: talent_pool, member: pool_person2)
    end

    it "creates a talent pool message" do
      message = described_class.send_to_talent_pool(
        production: production,
        sender: sender,
        subject: "Talent Pool Update",
        body: "Hello everyone"
      )

      expect(message).to be_persisted
      expect(message.production).to eq(production)
      expect(message.visibility).to eq("production")
      expect(message.message_type).to eq("talent_pool")
      expect(message.recipient?(pool_person1)).to be true
      expect(message.recipient?(pool_person2)).to be true
    end

    it "can filter to specific person_ids" do
      message = described_class.send_to_talent_pool(
        production: production,
        sender: sender,
        subject: "Targeted Message",
        body: "Just for you",
        person_ids: [ pool_person1.id ]
      )

      expect(message).to be_persisted
      expect(message.recipient?(pool_person1)).to be true
      expect(message.recipient?(pool_person2)).to be false
    end
  end

  describe ".send_to_production_team" do
    let(:manager_user) { create(:user) }
    let(:manager_person) { create(:person, user: manager_user) }
    let(:cast_person) { create(:person, user: create(:user)) }

    before do
      manager_user.update!(default_person: manager_person)
      create(:organization_role, organization: organization, user: manager_user, company_role: :manager)
    end

    it "creates a message to production team" do
      message = described_class.send_to_production_team(
        production: production,
        sender: cast_person.user,
        subject: "Question",
        body: "I have a question"
      )

      expect(message).to be_persisted
      expect(message.message_type).to eq("production_contact")
      expect(message.visibility).to eq("personal")
    end

    it "includes production managers as recipients" do
      message = described_class.send_to_production_team(
        production: production,
        sender: cast_person.user,
        subject: "Question",
        body: "Content"
      )

      expect(message.recipient?(manager_person)).to be true
    end
  end

  describe ".send_to_group" do
    let(:group) { create(:group) }
    let(:member1) { create(:person, user: create(:user)) }
    let(:member2) { create(:person, user: create(:user)) }

    before do
      create(:group_membership, group: group, person: member1)
      create(:group_membership, group: group, person: member2)
    end

    it "creates a message to all group members" do
      message = described_class.send_to_group(
        sender: sender,
        group: group,
        production: production,
        subject: "Group Message",
        body: "Hello group"
      )

      expect(message).to be_persisted
      expect(message.recipient?(member1)).to be true
      expect(message.recipient?(member2)).to be true
    end

    it "uses production visibility when no show specified" do
      message = described_class.send_to_group(
        sender: sender,
        group: group,
        production: production,
        subject: "Group Message",
        body: "Content"
      )

      expect(message.visibility).to eq("production")
    end

    it "uses show visibility when show specified" do
      message = described_class.send_to_group(
        sender: sender,
        group: group,
        subject: "Group Message",
        body: "Content",
        show: show,
        production: production
      )

      expect(message.visibility).to eq("show")
      expect(message.show).to eq(show)
    end
  end

  describe ".send_to_people" do
    let(:person1) { create(:person, user: create(:user)) }
    let(:person2) { create(:person, user: create(:user)) }

    it "creates a message to multiple people" do
      message = described_class.send_to_people(
        sender: sender,
        people: [ person1, person2 ],
        subject: "Batch Message",
        body: "Hello everyone"
      )

      expect(message).to be_persisted
      expect(message.recipient?(person1)).to be true
      expect(message.recipient?(person2)).to be true
    end

    it "defaults to direct message type" do
      message = described_class.send_to_people(
        sender: sender,
        people: [ person1 ],
        subject: "Message",
        body: "Content"
      )

      expect(message.message_type).to eq("direct")
    end

    it "can specify custom message type" do
      message = described_class.send_to_people(
        sender: sender,
        people: [ person1 ],
        subject: "Message",
        body: "Content",
        message_type: :talent_pool
      )

      expect(message.message_type).to eq("talent_pool")
    end
  end

  describe ".create_message" do
    it "filters out people without user accounts" do
      person_with_user = create(:person, user: create(:user))
      person_without_user = create(:person, user: nil)

      message = described_class.create_message(
        sender: sender,
        recipients: [ person_with_user, person_without_user ],
        subject: "Test",
        body: "Content",
        message_type: :direct
      )

      expect(message.recipient?(person_with_user)).to be true
      expect(message.recipient?(person_without_user)).to be false
    end

    it "returns nil when no valid recipients" do
      person_without_user = create(:person, user: nil)

      message = described_class.create_message(
        sender: sender,
        recipients: [ person_without_user ],
        subject: "Test",
        body: "Content",
        message_type: :direct
      )

      expect(message).to be_nil
    end

    it "inherits context from parent message" do
      parent = create(:message,
        sender: sender,
        production: production,
        show: show,
        visibility: :show,
        organization: organization
      )

      reply = described_class.create_message(
        sender: sender,
        recipients: [ recipient_person ],
        subject: "Re: Original",
        body: "Reply",
        message_type: :direct,
        parent_message: parent
      )

      expect(reply.production).to eq(production)
      expect(reply.show).to eq(show)
      expect(reply.visibility).to eq("show")
      expect(reply.organization).to eq(organization)
    end

    it "subscribes sender and marks as read" do
      message = described_class.create_message(
        sender: sender,
        recipients: [ recipient_person ],
        subject: "Test",
        body: "Content",
        message_type: :direct
      )

      subscription = MessageSubscription.find_by(user: sender, message: message)
      expect(subscription).to be_present
      expect(subscription.last_read_at).to be_present
    end

    it "subscribes recipients but does not mark as read" do
      message = described_class.create_message(
        sender: sender,
        recipients: [ recipient_person ],
        subject: "Test",
        body: "Content",
        message_type: :direct
      )

      subscription = MessageSubscription.find_by(user: recipient_user, message: message)
      expect(subscription).to be_present
      expect(subscription.last_read_at).to be_nil
    end

    context "with production visibility" do
      let(:manager) { create(:user) }

      before do
        create(:organization_role, organization: organization, user: manager, company_role: :manager)
      end

      it "subscribes production team" do
        message = described_class.create_message(
          sender: sender,
          recipients: [ recipient_person ],
          subject: "Production Update",
          body: "Content",
          message_type: :cast_contact,
          production: production,
          visibility: :production
        )

        expect(message.subscribed?(manager)).to be true
      end
    end
  end

  describe ".reply" do
    let(:original_sender) { create(:user) }
    let(:original_sender_person) { create(:person, user: original_sender) }
    let(:original_recipient_person) { create(:person, user: recipient_user) }
    let!(:original_message) do
      original_sender.update!(default_person: original_sender_person)
      described_class.send_direct(
        sender: original_sender,
        recipient_person: original_recipient_person,
        subject: "Original",
        body: "Original content"
      )
    end

    context "when original recipient replies" do
      it "sends reply to original sender" do
        reply = described_class.reply(
          sender: recipient_user,
          parent_message: original_message,
          body: "Reply content"
        )

        expect(reply).to be_persisted
        expect(reply.parent_message).to eq(original_message)
        expect(reply.recipient?(original_sender_person)).to be true
      end
    end

    context "when original sender replies" do
      it "sends reply to original recipients" do
        reply = described_class.reply(
          sender: original_sender,
          parent_message: original_message,
          body: "Follow-up"
        )

        expect(reply).to be_persisted
        expect(reply.recipient?(original_recipient_person)).to be true
      end
    end

    it "prefixes subject with Re:" do
      reply = described_class.reply(
        sender: recipient_user,
        parent_message: original_message,
        body: "Reply"
      )

      expect(reply.subject).to eq("Re: Original")
    end

    it "inherits message type from root" do
      reply = described_class.reply(
        sender: recipient_user,
        parent_message: original_message,
        body: "Reply"
      )

      expect(reply.message_type).to eq(original_message.message_type)
    end
  end
end
