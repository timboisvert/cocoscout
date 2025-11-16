require "rails_helper"

RSpec.describe EmailLogInterceptor do
  let(:user) { create(:user) }

  describe ".delivering_email" do
    it "creates an email log when sending an email" do
      expect {
        AuthMailer.signup(user).deliver_now
      }.to change(EmailLog, :count).by(1)

      log = EmailLog.last
      expect(log.user).to eq(user)
      expect(log.recipient).to eq(user.email_address)
      expect(log.subject).to eq("Welcome to CocoScout")
      expect(log.mailer_class).to eq("AuthMailer")
      expect(log.mailer_action).to eq("signup")
      expect(log.delivery_status).to eq("queued")
      expect(log.sent_at).to be_present
    end

    it "does not fail email delivery if logging fails" do
      allow(EmailLog).to receive(:create!).and_raise(StandardError.new("Database error"))

      expect {
        AuthMailer.signup(user).deliver_now
      }.not_to raise_error

      # Email should still be sent even if logging fails
      expect(ActionMailer::Base.deliveries.last.to).to include(user.email_address)
    end

    it "logs emails from person mailer" do
      person = create(:person)

      expect {
        Manage::PersonMailer.contact_email(person, "Test Subject", "Test message", user).deliver_now
      }.to change(EmailLog, :count).by(1)

      log = EmailLog.last
      expect(log.user).to eq(user)
      expect(log.recipient).to eq(person.email)
      expect(log.subject).to eq("Test Subject")
    end
  end
end
