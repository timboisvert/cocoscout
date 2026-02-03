# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContentTemplateService do
  before do
    # Clear any existing templates from seeds
    ContentTemplate.destroy_all
  end

  describe ".render" do
    let!(:template) do
      create(:content_template,
             key: "test_template",
             subject: "Hello {{recipient_name}}!",
             body: "Dear {{recipient_name}}, welcome to {{company}}.")
    end

    it "renders a template with variables" do
      result = ContentTemplateService.render("test_template", {
                                               recipient_name: "John",
                                               company: "CocoScout"
                                             })

      expect(result[:subject]).to eq("Hello John!")
      expect(result[:body]).to eq("Dear John, welcome to CocoScout.")
    end

    it "raises error for non-existent template" do
      expect {
        ContentTemplateService.render("nonexistent")
      }.to raise_error(ContentTemplateService::TemplateNotFoundError)
    end

    context "with strict mode" do
      it "raises error for missing variables" do
        expect {
          ContentTemplateService.render("test_template", { recipient_name: "John" }, strict: true)
        }.to raise_error(ContentTemplateService::MissingVariablesError, /company/)
      end

      it "passes when all variables provided" do
        expect {
          ContentTemplateService.render("test_template",
                                        { recipient_name: "John", company: "Acme" },
                                        strict: true)
        }.not_to raise_error
      end
    end
  end

  describe ".exists?" do
    it "returns true for existing active template" do
      create(:content_template, key: "existing", active: true)

      expect(ContentTemplateService.exists?("existing")).to be true
    end

    it "returns false for inactive template" do
      create(:content_template, key: "inactive", active: false)

      expect(ContentTemplateService.exists?("inactive")).to be false
    end

    it "returns false for non-existent template" do
      expect(ContentTemplateService.exists?("nonexistent")).to be false
    end
  end

  describe ".upsert" do
    it "creates a new template" do
      template = ContentTemplateService.upsert("new_template",
                                               name: "New Template",
                                               subject: "Hello",
                                               body: "World")

      expect(template).to be_persisted
      expect(template.key).to eq("new_template")
      expect(template.name).to eq("New Template")
    end

    it "updates existing template" do
      create(:content_template, key: "existing", name: "Old Name")

      template = ContentTemplateService.upsert("existing", name: "New Name")

      expect(template.name).to eq("New Name")
      expect(ContentTemplate.where(key: "existing").count).to eq(1)
    end
  end

  describe ".preview" do
    let!(:template) do
      create(:content_template,
             key: "preview_test",
             subject: "Hello {{recipient_name}}!",
             body: "Welcome {{recipient_name}} to {{company_name}}.",
             available_variables: [
               { name: "recipient_name", description: "Recipient's name" },
               { name: "company_name", description: "Company name" }
             ])
    end

    it "returns preview with sample data" do
      result = ContentTemplateService.preview("preview_test")

      # Sample values now use more realistic names based on variable name patterns
      expect(result[:subject]).to include("Sarah Johnson") # Sample value for recipient_name
      expect(result[:variables_used]).to contain_exactly("recipient_name", "company_name")
      expect(result[:available_variables]).to be_present
    end

    it "accepts custom sample variables" do
      result = ContentTemplateService.preview("preview_test",
                                              recipient_name: "Jane Doe",
                                              company_name: "Acme Corp")

      expect(result[:subject]).to eq("Hello Jane Doe!")
      expect(result[:body]).to include("Acme Corp")
    end
  end

  describe ".channel_for" do
    it "returns channel for template" do
      create(:content_template, key: "email_only", channel: :email)
      create(:content_template, key: "message_only", channel: :message)
      create(:content_template, key: "both_channels", channel: :both)

      expect(ContentTemplateService.channel_for("email_only")).to eq(:email)
      expect(ContentTemplateService.channel_for("message_only")).to eq(:message)
      expect(ContentTemplateService.channel_for("both_channels")).to eq(:both)
    end

    it "defaults to email for missing template" do
      expect(ContentTemplateService.channel_for("nonexistent")).to eq(:email)
    end
  end

  describe ".sends_message?" do
    it "returns true for message channel" do
      create(:content_template, key: "message_template", channel: :message)
      expect(ContentTemplateService.sends_message?("message_template")).to be true
    end

    it "returns true for both channel" do
      create(:content_template, key: "both_template", channel: :both)
      expect(ContentTemplateService.sends_message?("both_template")).to be true
    end

    it "returns false for email-only channel" do
      create(:content_template, key: "email_template", channel: :email)
      expect(ContentTemplateService.sends_message?("email_template")).to be false
    end
  end

  describe ".sends_email?" do
    it "returns true for email channel" do
      create(:content_template, key: "email_template", channel: :email)
      expect(ContentTemplateService.sends_email?("email_template")).to be true
    end

    it "returns true for both channel" do
      create(:content_template, key: "both_template", channel: :both)
      expect(ContentTemplateService.sends_email?("both_template")).to be true
    end

    it "returns false for message-only channel" do
      create(:content_template, key: "message_template", channel: :message)
      expect(ContentTemplateService.sends_email?("message_template")).to be false
    end
  end

  describe ".deliver" do
    let(:sender) { create(:user) }
    let(:recipient_user) { create(:user) }
    let(:recipient) { create(:person, user: recipient_user, email: recipient_user.email_address) }
    let(:production) { create(:production) }

    context "with message channel template" do
      let!(:template) do
        create(:content_template,
               key: "message_notification",
               subject: "Hello {{name}}",
               body: "Welcome {{name}}!",
               channel: :message)
      end

      it "creates an in-app message" do
        result = ContentTemplateService.deliver(
          template_key: "message_notification",
          variables: { name: "John" },
          sender: sender,
          recipients: [ recipient ],
          production: production,
          message_type: :system
        )

        expect(result[:channel]).to eq(:message)
        expect(result[:messages]).not_to be_empty
        expect(result[:emails_queued]).to eq(0)
      end

      it "uses MessageService to create the message" do
        expect(MessageService).to receive(:create_message).and_call_original

        ContentTemplateService.deliver(
          template_key: "message_notification",
          variables: { name: "John" },
          sender: sender,
          recipients: [ recipient ],
          message_type: :system
        )
      end

      it "does not send email for message-only template" do
        result = ContentTemplateService.deliver(
          template_key: "message_notification",
          variables: { name: "John" },
          sender: sender,
          recipients: [ recipient ],
          message_type: :system
        )

        expect(result[:emails_queued]).to eq(0)
      end
    end

    context "with email channel template" do
      let!(:template) do
        create(:content_template,
               key: "email_notification",
               subject: "Email to {{name}}",
               body: "Email body for {{name}}",
               channel: :email)
      end

      it "queues emails for delivery" do
        mailer_double = double("mailer")
        allow(mailer_double).to receive(:deliver_later)

        # Stub the mailer to prevent actual email delivery
        allow_any_instance_of(Class).to receive(:send).and_return(mailer_double)

        result = ContentTemplateService.deliver(
          template_key: "email_notification",
          variables: { name: "Jane" },
          sender: sender,
          recipients: [ recipient ],
          mailer_class: Manage::AuditionMailer,
          mailer_method: :casting_notification
        )

        expect(result[:channel]).to eq(:email)
        expect(result[:messages]).to be_empty
      end

      it "skips recipients without email" do
        recipient_no_email = create(:person)
        recipient_no_email.update_column(:email, nil)  # Bypass validation to test edge case

        result = ContentTemplateService.deliver(
          template_key: "email_notification",
          variables: { name: "Test" },
          sender: sender,
          recipients: [ recipient_no_email ],
          mailer_class: Manage::AuditionMailer,
          mailer_method: :casting_notification
        )

        expect(result[:emails_queued]).to eq(0)
      end
    end

    context "with both channel template" do
      let!(:template) do
        create(:content_template,
               key: "dual_notification",
               subject: "Notice for {{name}}",
               body: "Important notice for {{name}}",
               channel: :both)
      end

      it "creates both message and queues email" do
        mailer_double = double("mailer")
        allow(mailer_double).to receive(:deliver_later)
        allow(Manage::AuditionMailer).to receive(:casting_notification).and_return(mailer_double)

        result = ContentTemplateService.deliver(
          template_key: "dual_notification",
          variables: { name: "Both" },
          sender: sender,
          recipients: [ recipient ],
          production: production,
          message_type: :system,
          mailer_class: Manage::AuditionMailer,
          mailer_method: :casting_notification
        )

        expect(result[:channel]).to eq(:both)
        expect(result[:messages]).not_to be_empty
        expect(result[:emails_queued]).to eq(1)
      end
    end

    it "passes email_batch to mailer" do
      template = create(:content_template,
                        key: "batch_email",
                        subject: "Batch",
                        body: "Content",
                        channel: :email)

      email_batch = EmailBatch.create!(
        user: sender,
        subject: "Test Batch",
        recipient_count: 1,
        sent_at: Time.current
      )

      mailer_double = double("mailer")
      allow(mailer_double).to receive(:deliver_later)

      expect(Manage::AuditionMailer).to receive(:casting_notification)
        .with(recipient, anything, anything, anything, hash_including(email_batch_id: email_batch.id))
        .and_return(mailer_double)

      ContentTemplateService.deliver(
        template_key: "batch_email",
        variables: {},
        sender: sender,
        recipients: [ recipient ],
        mailer_class: Manage::AuditionMailer,
        mailer_method: :casting_notification,
        email_batch: email_batch
      )
    end
  end

  describe ".deliver_batch" do
    let(:sender) { create(:user) }
    let(:person1) { create(:person, user: create(:user)) }
    let(:person2) { create(:person, user: create(:user)) }

    let!(:template) do
      create(:content_template,
             key: "batch_template",
             subject: "Hello {{name}}",
             body: "Welcome {{name}}!",
             channel: :message)
    end

    it "delivers to multiple recipients" do
      result = ContentTemplateService.deliver_batch(
        template_key: "batch_template",
        recipient_variables: [
          { person: person1, variables: { name: "Alice" } },
          { person: person2, variables: { name: "Bob" } }
        ],
        sender: sender,
        message_type: :system
      )

      expect(result[:messages]).not_to be_empty
    end

    it "raises error for non-existent template" do
      expect {
        ContentTemplateService.deliver_batch(
          template_key: "nonexistent",
          recipient_variables: [ { person: person1, variables: {} } ],
          sender: sender,
          message_type: :system
        )
      }.to raise_error(ContentTemplateService::TemplateNotFoundError)
    end
  end
end
