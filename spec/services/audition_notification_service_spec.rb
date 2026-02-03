# frozen_string_literal: true

require "rails_helper"

RSpec.describe AuditionNotificationService do
  let(:organization) { create(:organization) }
  let(:production) { create(:production, organization: organization) }
  let(:audition_cycle) { create(:audition_cycle, production: production) }
  let(:sender) { create(:user) }
  let(:recipient_user) { create(:user) }
  let(:person) { create(:person, user: recipient_user, email: recipient_user.email_address) }
  let(:person_without_user) { create(:person, email: "guest@example.com") }

  describe ".send_casting_results" do
    before do
      # Create casting template
      ContentTemplate.create!(
        key: "audition_added_to_cast",
        name: "Added to Cast",
        subject: "Welcome to {{production_name}}",
        body: "<p>Congratulations!</p>",
        channel: "message",
        active: true
      )

      # Create rejection template
      ContentTemplate.create!(
        key: "audition_not_cast",
        name: "Not Cast",
        subject: "Thank you for auditioning",
        body: "<p>Unfortunately...</p>",
        channel: "message",
        active: true
      )
    end

    context "with message channel template" do
      it "sends messages to users with accounts" do
        talent_pool = create(:talent_pool, production: production)

        result = described_class.send_casting_results(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
          rejections: []
        )

        expect(result[:messages_sent]).to eq(1)
        expect(result[:emails_sent]).to eq(0)
      end

      it "sends emails to people without accounts" do
        talent_pool = create(:talent_pool, production: production)

        result = described_class.send_casting_results(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          cast_assignments: [ { person: person_without_user, talent_pool: talent_pool, body: "Welcome!" } ],
          rejections: []
        )

        expect(result[:messages_sent]).to eq(0)
        expect(result[:emails_sent]).to eq(1)
      end

      it "processes both cast assignments and rejections" do
        talent_pool = create(:talent_pool, production: production)
        rejected_user = create(:user)
        rejected_person = create(:person, user: rejected_user, email: rejected_user.email_address)

        result = described_class.send_casting_results(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
          rejections: [ { person: rejected_person, body: "Thank you for your interest." } ]
        )

        expect(result[:messages_sent]).to eq(2)
        expect(result[:emails_sent]).to eq(0)
      end
    end

    context "with email channel template" do
      before do
        ContentTemplate.find_by(key: "audition_added_to_cast").update!(channel: "email")
      end

      it "sends emails instead of messages" do
        talent_pool = create(:talent_pool, production: production)

        result = described_class.send_casting_results(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
          rejections: []
        )

        expect(result[:messages_sent]).to eq(0)
        expect(result[:emails_sent]).to eq(1)
      end
    end

    context "with both channel template" do
      before do
        ContentTemplate.find_by(key: "audition_added_to_cast").update!(channel: "both")
      end

      it "sends both message and email" do
        talent_pool = create(:talent_pool, production: production)

        result = described_class.send_casting_results(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
          rejections: []
        )

        expect(result[:messages_sent]).to eq(1)
        expect(result[:emails_sent]).to eq(1)
      end
    end

    it "uses custom subject when provided" do
      talent_pool = create(:talent_pool, production: production)

      expect(MessageService).to receive(:send_direct).with(
        hash_including(subject: "Custom Subject Here")
      ).and_call_original

      described_class.send_casting_results(
        production: production,
        audition_cycle: audition_cycle,
        sender: sender,
        cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!", subject: "Custom Subject Here" } ],
        rejections: []
      )
    end
  end

  describe ".send_audition_invitations" do
    before do
      # Create invitation template
      ContentTemplate.create!(
        key: "audition_invitation",
        name: "Audition Invitation",
        subject: "You're invited to audition",
        body: "<p>Please come audition!</p>",
        channel: "message",
        active: true
      )

      # Create not invited template
      ContentTemplate.create!(
        key: "audition_not_invited",
        name: "Not Invited",
        subject: "Audition Update",
        body: "<p>Unfortunately...</p>",
        channel: "message",
        active: true
      )
    end

    context "with message channel template" do
      it "sends messages to users with accounts" do
        result = described_class.send_audition_invitations(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          invitations: [ { person: person, body: "You're invited!" } ],
          not_invited: []
        )

        expect(result[:messages_sent]).to eq(1)
        expect(result[:emails_sent]).to eq(0)
      end

      it "sends emails to people without accounts" do
        result = described_class.send_audition_invitations(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          invitations: [ { person: person_without_user, body: "You're invited!" } ],
          not_invited: []
        )

        expect(result[:messages_sent]).to eq(0)
        expect(result[:emails_sent]).to eq(1)
      end

      it "processes both invitations and not invited" do
        not_invited_user = create(:user)
        not_invited_person = create(:person, user: not_invited_user, email: not_invited_user.email_address)

        result = described_class.send_audition_invitations(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          invitations: [ { person: person, body: "You're invited!" } ],
          not_invited: [ { person: not_invited_person, body: "Sorry, not this time." } ]
        )

        expect(result[:messages_sent]).to eq(2)
        expect(result[:emails_sent]).to eq(0)
      end
    end

    context "with email channel template" do
      before do
        ContentTemplate.find_by(key: "audition_invitation").update!(channel: "email")
      end

      it "sends emails using invitation_notification mailer" do
        expect(Manage::AuditionMailer).to receive(:invitation_notification)
          .with(person, production, "You're invited!", email_batch_id: nil)
          .and_call_original

        described_class.send_audition_invitations(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          invitations: [ { person: person, body: "You're invited!" } ],
          not_invited: []
        )
      end
    end

    it "skips people with blank email addresses" do
      blank_email_person = build(:person, email: "")
      # Bypass validation to create person without email
      blank_email_person.save(validate: false)

      result = described_class.send_audition_invitations(
        production: production,
        audition_cycle: audition_cycle,
        sender: sender,
        invitations: [ { person: blank_email_person, body: "You're invited!" } ],
        not_invited: []
      )

      expect(result[:messages_sent]).to eq(0)
      expect(result[:emails_sent]).to eq(0)
    end
  end

  describe "notification preferences" do
    before do
      ContentTemplate.create!(
        key: "audition_added_to_cast",
        name: "Added to Cast",
        subject: "Welcome",
        body: "<p>Congratulations!</p>",
        channel: "email",
        active: true
      )
    end

    it "respects user notification preferences for audition_results" do
      # Disable audition_results notifications for this user
      recipient_user.update!(notification_preferences: { "audition_results" => false })

      talent_pool = create(:talent_pool, production: production)

      result = described_class.send_casting_results(
        production: production,
        audition_cycle: audition_cycle,
        sender: sender,
        cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
        rejections: []
      )

      expect(result[:emails_sent]).to eq(0)
    end
  end

  describe "email batch tracking" do
    before do
      ContentTemplate.create!(
        key: "audition_added_to_cast",
        name: "Added to Cast",
        subject: "Welcome",
        body: "<p>Congratulations!</p>",
        channel: "email",
        active: true
      )
    end

    it "passes email_batch_id to mailer" do
      email_batch = EmailBatch.create!(
        user: sender,
        subject: "Test Batch",
        recipient_count: 1,
        sent_at: Time.current
      )

      talent_pool = create(:talent_pool, production: production)

      expect(Manage::AuditionMailer).to receive(:casting_notification)
        .with(person, production, "Welcome!", subject: anything, email_batch_id: email_batch.id)
        .and_call_original

      described_class.send_casting_results(
        production: production,
        audition_cycle: audition_cycle,
        sender: sender,
        cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
        rejections: [],
        email_batch: email_batch
      )
    end
  end
end
