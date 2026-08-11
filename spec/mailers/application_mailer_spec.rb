# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationMailer do
  # Minimal concrete mailer to exercise the recipient gate in ApplicationMailer#mail
  class RecipientGateTestMailer < ApplicationMailer
    def hello(to)
      mail(to: to, subject: 'Hello') do |format|
        format.text { render plain: 'hi' }
      end
    end
  end

  describe 'invalid recipient gate' do
    it 'sends to a valid address' do
      message = RecipientGateTestMailer.hello('someone@example.com').message
      expect(message).to be_a(Mail::Message)
      expect(message.to).to eq([ 'someone@example.com' ])
    end

    it 'accepts a display-name address' do
      message = RecipientGateTestMailer.hello('Some One <someone@example.com>').message
      expect(message).to be_a(Mail::Message)
    end

    it 'refuses to build a message for a malformed address' do
      message = RecipientGateTestMailer.hello('someone@gmail,com').message
      expect(message).to be_a(ActionMailer::Base::NullMail)
    end

    it 'refuses to build a message for a blank address' do
      message = RecipientGateTestMailer.hello('').message
      expect(message).to be_a(ActionMailer::Base::NullMail)
    end

    it 'refuses to build a message for a nil address' do
      message = RecipientGateTestMailer.hello(nil).message
      expect(message).to be_a(ActionMailer::Base::NullMail)
    end
  end
end
