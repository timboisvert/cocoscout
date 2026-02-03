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
      # Update or create casting template for tests
      ContentTemplate.find_or_create_by!(key: "audition_added_to_cast") do |t|
        t.name = "Added to Cast"
        t.subject = "Welcome to {{production_name}}"
        t.body = "<p>Congratulations!</p>"
        t.channel = "message"
        t.active = true
      end.tap do |t|
        t.update!(channel: "message") # Ensure channel is set correctly for test
      end

      # Update or create rejection template for tests
      ContentTemplate.find_or_create_by!(key: "audition_not_cast") do |t|
        t.name = "Not Cast"
        t.subject = "Thank you for auditioning"
        t.body = "<p>Unfortunately...</p>"
        t.channel = "message"
        t.active = true
      end.tap do |t|
        t.update!(channel: "message")
      end
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

      it "skips people without accounts (message-only)" do
        talent_pool = create(:talent_pool, production: production)

        result = described_class.send_casting_results(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          cast_assignments: [ { person: person_without_user, talent_pool: talent_pool, body: "Welcome!" } ],
          rejections: []
        )

        # Service is message-only, so no notification for users without accounts
        expect(result[:messages_sent]).to eq(0)
        expect(result[:emails_sent]).to eq(0)
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

    context "with email channel template (ignored - service is message-only)" do
      before do
        ContentTemplate.find_by(key: "audition_added_to_cast").update!(channel: "email")
      end

      it "still sends messages regardless of template channel" do
        talent_pool = create(:talent_pool, production: production)

        result = described_class.send_casting_results(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
          rejections: []
        )

        # Service is message-only, ignores template channel setting
        expect(result[:messages_sent]).to eq(1)
        expect(result[:emails_sent]).to eq(0)
      end
    end

    context "with both channel template (ignored - service is message-only)" do
      before do
        ContentTemplate.find_by(key: "audition_added_to_cast").update!(channel: "both")
      end

      it "still sends only messages regardless of template channel" do
        talent_pool = create(:talent_pool, production: production)

        result = described_class.send_casting_results(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
          rejections: []
        )

        # Service is message-only, ignores template channel setting
        expect(result[:messages_sent]).to eq(1)
        expect(result[:emails_sent]).to eq(0)
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
      # Update invitation template for tests
      ContentTemplate.find_or_create_by!(key: "audition_invitation") do |t|
        t.name = "Audition Invitation"
        t.subject = "You're invited to audition"
        t.body = "<p>Please come audition!</p>"
        t.channel = "message"
        t.active = true
      end.tap { |t| t.update!(channel: "message") }

      # Update not invited template for tests
      ContentTemplate.find_or_create_by!(key: "audition_not_invited") do |t|
        t.name = "Not Invited"
        t.subject = "Audition Update"
        t.body = "<p>Unfortunately...</p>"
        t.channel = "message"
        t.active = true
      end.tap { |t| t.update!(channel: "message") }
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

      it "skips people without accounts (message-only)" do
        result = described_class.send_audition_invitations(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          invitations: [ { person: person_without_user, body: "You're invited!" } ],
          not_invited: []
        )

        # Service is message-only, so no notification for users without accounts
        expect(result[:messages_sent]).to eq(0)
        expect(result[:emails_sent]).to eq(0)
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

    context "with email channel template (ignored - service is message-only)" do
      before do
        ContentTemplate.find_by(key: "audition_invitation").update!(channel: "email")
      end

      it "still sends messages regardless of template channel" do
        result = described_class.send_audition_invitations(
          production: production,
          audition_cycle: audition_cycle,
          sender: sender,
          invitations: [ { person: person, body: "You're invited!" } ],
          not_invited: []
        )

        # Service is message-only, ignores template channel setting
        expect(result[:messages_sent]).to eq(1)
        expect(result[:emails_sent]).to eq(0)
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
      ContentTemplate.find_or_create_by!(key: "audition_added_to_cast") do |t|
        t.name = "Added to Cast"
        t.subject = "Welcome"
        t.body = "<p>Congratulations!</p>"
        t.channel = "email"
        t.active = true
      end.tap { |t| t.update!(channel: "email") }
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

  describe "email batch tracking (ignored - service is message-only)" do
    before do
      ContentTemplate.find_or_create_by!(key: "audition_added_to_cast") do |t|
        t.name = "Added to Cast"
        t.subject = "Welcome"
        t.body = "<p>Congratulations!</p>"
        t.channel = "email"
        t.active = true
      end.tap { |t| t.update!(channel: "email") }
    end

    it "sends messages regardless of email_batch (service is message-only)" do
      email_batch = EmailBatch.create!(
        user: sender,
        subject: "Test Batch",
        recipient_count: 1,
        sent_at: Time.current
      )

      talent_pool = create(:talent_pool, production: production)

      # Service is message-only, so emails are not sent and mailer is not called
      expect(Manage::AuditionMailer).not_to receive(:casting_notification)

      result = described_class.send_casting_results(
        production: production,
        audition_cycle: audition_cycle,
        sender: sender,
        cast_assignments: [ { person: person, talent_pool: talent_pool, body: "Welcome!" } ],
        rejections: [],
        email_batch: email_batch
      )

      expect(result[:messages_sent]).to eq(1)
      expect(result[:emails_sent]).to eq(0)
    end
  end
end
