# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailLog, type: :model do
  describe 'associations' do
    it 'belongs to a user' do
      log = build(:email_log)
      expect(log).to respond_to(:user)
    end

    it 'optionally belongs to a recipient_entity' do
      log = build(:email_log)
      expect(log).to respond_to(:recipient_entity)
    end

    it 'optionally belongs to an email_batch' do
      log = build(:email_log)
      expect(log).to respond_to(:email_batch)
    end

    it 'optionally belongs to an organization' do
      log = build(:email_log)
      expect(log).to respond_to(:organization)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:email_log)).to be_valid
    end

    it 'is invalid without a recipient' do
      log = build(:email_log, recipient: nil)
      expect(log).not_to be_valid
      expect(log.errors[:recipient]).to include("can't be blank")
    end
  end

  describe 'scopes' do
    describe '.sent' do
      it 'returns only logs with sent_at' do
        sent = create(:email_log, sent_at: Time.current)
        unsent = create(:email_log, sent_at: nil)

        expect(described_class.sent).to include(sent)
        expect(described_class.sent).not_to include(unsent)
      end
    end

    describe '.delivered' do
      it 'returns only logs with delivered status' do
        delivered = create(:email_log, delivery_status: 'delivered')
        failed = create(:email_log, delivery_status: 'failed')

        expect(described_class.delivered).to include(delivered)
        expect(described_class.delivered).not_to include(failed)
      end
    end

    describe '.failed' do
      it 'returns only logs with failed status' do
        delivered = create(:email_log, delivery_status: 'delivered')
        failed = create(:email_log, delivery_status: 'failed')

        expect(described_class.failed).to include(failed)
        expect(described_class.failed).not_to include(delivered)
      end
    end

    describe '.for_user' do
      it 'filters by user' do
        user = create(:user)
        other_user = create(:user)
        log1 = create(:email_log, user: user)
        log2 = create(:email_log, user: other_user)

        expect(described_class.for_user(user)).to include(log1)
        expect(described_class.for_user(user)).not_to include(log2)
      end
    end
  end

  describe '#delivered?' do
    it 'returns true when delivery_status is delivered' do
      log = build(:email_log, delivery_status: 'delivered')
      expect(log.delivered?).to be true
    end

    it 'returns false otherwise' do
      log = build(:email_log, delivery_status: 'pending')
      expect(log.delivered?).to be false
    end
  end

  describe '#failed?' do
    it 'returns true when delivery_status is failed' do
      log = build(:email_log, delivery_status: 'failed')
      expect(log.failed?).to be true
    end

    it 'returns false otherwise' do
      log = build(:email_log, delivery_status: 'delivered')
      expect(log.failed?).to be false
    end
  end

  describe '#pending?' do
    it 'returns true when delivery_status is pending' do
      log = build(:email_log, delivery_status: 'pending')
      expect(log.pending?).to be true
    end

    it 'returns false otherwise' do
      log = build(:email_log, delivery_status: 'delivered')
      expect(log.pending?).to be false
    end
  end
end
