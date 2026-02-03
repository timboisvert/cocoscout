# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailLogInterceptor do
  let(:user) { create(:user) }

  describe '.delivering_email' do
    it 'creates an email log when sending an email' do
      expect do
        AuthMailer.signup(user).deliver_now
      end.to change(EmailLog, :count).by(1)

      log = EmailLog.last
      expect(log.user).to eq(user)
      expect(log.recipient).to eq(user.email_address)
      expect(log.subject).to eq('Welcome to CocoScout')
      expect(log.mailer_class).to eq('AuthMailer')
      expect(log.mailer_action).to eq('signup')
      expect(log.delivery_status).to eq('queued')
      expect(log.sent_at).to be_present
    end

    it 'does not fail email delivery if logging fails' do
      allow(EmailLog).to receive(:create!).and_raise(StandardError.new('Database error'))

      expect do
        AuthMailer.signup(user).deliver_now
      end.not_to raise_error

      # Email should still be sent even if logging fails
      expect(ActionMailer::Base.deliveries.last.to).to include(user.email_address)
    end

    it 'logs emails from person mailer' do
      organization = create(:organization)
      recipient_user = create(:user)
      person_invitation = create(:person_invitation, organization: organization, email: recipient_user.email_address)
      # Create a person with the same email linked to the user so the interceptor can resolve
      create(:person, email: recipient_user.email_address, user: recipient_user)

      expect do
        Manage::PersonMailer.person_invitation(person_invitation, 'Test Subject', 'Test message').deliver_now
      end.to change(EmailLog, :count).by(1)

      log = EmailLog.last
      expect(log.recipient).to eq(person_invitation.email)
      expect(log.subject).to eq('Test Subject')
    end

    it 'falls back to email_batch.user when recipient has no linked user' do
      sender = create(:user)
      email_batch = EmailBatch.create!(user: sender, subject: 'Batch', recipient_count: 2, sent_at: Time.current)
      production = create(:production)

      # Person without a linked user
      person = create(:person, user: nil, email: 'no_user@example.com')

      expect do
        Manage::AuditionMailer.casting_notification(person, production, '<p>hi</p>', subject: 'You have been cast!', email_batch_id: email_batch.id).deliver_now
      end.to change(EmailLog, :count).by(1)

      log = EmailLog.last
      expect(log.user).to eq(sender)
      expect(log.recipient).to eq(person.email)
    end
  end
end
