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

    it 'logs emails from person mailer and associates with person record' do
      person = create(:person)

      expect do
        Manage::PersonMailer.contact_email(person, 'Test Subject', 'Test message', user).deliver_now
      end.to change(EmailLog, :count).by(1)

      log = EmailLog.last
      expect(log.user).to eq(user)
      expect(log.recipient).to eq(person.email)
      expect(log.subject).to eq('Test Subject')
      expect(log.recipient_type).to eq('Person')
      expect(log.recipient_id).to eq(person.id)
    end

    it 'logs emails to groups and associates with group record' do
      group = create(:group)

      expect do
        Manage::ContactMailer.send_message(group, 'Group Email', 'Message body', user).deliver_now
      end.to change(EmailLog, :count).by(1)

      log = EmailLog.last
      expect(log.user).to eq(user)
      expect(log.recipient).to eq(group.email)
      expect(log.subject).to eq('Group Email')
      expect(log.recipient_type).to eq('Group')
      expect(log.recipient_id).to eq(group.id)
    end

    it 'handles emails to recipients without a Person or Group record' do
      user = create(:user)
      email_address = 'unknown@example.com'
      
      # Create a test mailer that sends to an arbitrary email
      allow_any_instance_of(Mail::Message).to receive(:to).and_return([email_address])
      
      expect do
        AuthMailer.signup(user).deliver_now
      end.to change(EmailLog, :count).by(1)

      log = EmailLog.last
      expect(log.recipient_type).to be_nil
      expect(log.recipient_id).to be_nil
    end
  end
end
