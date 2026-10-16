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

  class FooterTestMailer < ApplicationMailer
    def hello
      mail(to: 'someone@example.com', subject: 'Hello') do |format|
        format.html { render html: '<p>hi</p>'.html_safe, layout: 'mailer' }
      end
    end
  end

  # Email apps drop web fonts, so the footer's CocoScout in Coustard is an
  # inline image, not text that falls back to Times (Tim, 2026-10-16).
  it 'signs the footer with the Coustard wordmark as an inline image' do
    message = FooterTestMailer.hello.message
    wordmark = message.attachments['cocoscout_wordmark.png']
    expect(wordmark).to be_present
    expect(wordmark).to be_inline
    expect(message.html_part.decoded).to include(%(src="cid:#{wordmark.content_id.delete('<>')}"), 'alt="CocoScout"')
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
