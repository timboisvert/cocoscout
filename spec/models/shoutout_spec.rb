# frozen_string_literal: true

require 'rails_helper'

describe Shoutout, type: :model do
  it 'is valid with valid attributes' do
    author = create(:person)
    shoutee = create(:person)
    shoutout = build(:shoutout, author: author, shoutee: shoutee)
    expect(shoutout).to be_valid
  end

  it 'is invalid without content' do
    shoutout = build(:shoutout, content: nil)
    expect(shoutout).not_to be_valid
  end

  it 'is invalid without an author' do
    shoutout = build(:shoutout, author: nil)
    expect(shoutout).not_to be_valid
  end

  it 'is invalid without a shoutee' do
    shoutout = build(:shoutout, shoutee: nil)
    expect(shoutout).not_to be_valid
  end

  it 'can have a Person as shoutee' do
    person = create(:person)
    shoutout = create(:shoutout, shoutee: person)
    expect(shoutout.shoutee).to eq(person)
    expect(shoutout.shoutee_type).to eq('Person')
  end

  it 'can have a Group as shoutee' do
    group = create(:group)
    author = create(:person)
    shoutout = create(:shoutout, shoutee: group, author: author)
    expect(shoutout.shoutee).to eq(group)
    expect(shoutout.shoutee_type).to eq('Group')
  end

  describe '#preview' do
    it 'returns truncated content' do
      shoutout = build(:shoutout, content: 'A' * 200)
      expect(shoutout.preview(length: 50).length).to be <= 53 # 50 + "..."
    end

    it 'returns full content if shorter than preview length' do
      shoutout = build(:shoutout, content: 'Short message')
      expect(shoutout.preview).to eq('Short message')
    end
  end

  describe 'scopes' do
    let!(:author) { create(:person) }
    let!(:recipient) { create(:person) }
    let!(:older_shoutout) { create(:shoutout, author: author, shoutee: recipient, created_at: 2.days.ago) }
    let!(:newer_shoutout) { create(:shoutout, author: author, shoutee: recipient, created_at: 1.day.ago) }

    describe '.newest_first' do
      it 'orders shoutouts by created_at descending' do
        expect(Shoutout.newest_first.first).to eq(newer_shoutout)
        expect(Shoutout.newest_first.last).to eq(older_shoutout)
      end
    end

    describe '.for_entity' do
      it 'returns shoutouts for a specific entity' do
        other_person = create(:person)
        other_shoutout = create(:shoutout, shoutee: other_person)

        expect(Shoutout.for_entity(recipient)).to include(older_shoutout, newer_shoutout)
        expect(Shoutout.for_entity(recipient)).not_to include(other_shoutout)
      end
    end

    describe '.by_author' do
      it 'returns shoutouts by a specific author' do
        other_author = create(:person)
        other_shoutout = create(:shoutout, author: other_author)

        expect(Shoutout.by_author(author)).to include(older_shoutout, newer_shoutout)
        expect(Shoutout.by_author(author)).not_to include(other_shoutout)
      end
    end
  end
end
