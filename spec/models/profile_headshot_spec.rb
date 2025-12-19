# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProfileHeadshot, type: :model do
  describe 'associations' do
    it 'belongs to a profileable' do
      headshot = build(:profile_headshot)
      expect(headshot).to respond_to(:profileable)
    end

    it 'has an attached image' do
      headshot = build(:profile_headshot)
      expect(headshot).to respond_to(:image)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(build(:profile_headshot)).to be_valid
    end

    it 'validates position is a non-negative integer' do
      headshot = build(:profile_headshot, position: -1)
      expect(headshot).not_to be_valid
    end

    it 'validates category is in the allowed list' do
      headshot = build(:profile_headshot, category: 'theatrical')
      expect(headshot).to be_valid

      headshot.category = 'invalid'
      expect(headshot).not_to be_valid
    end

    it 'allows blank category' do
      headshot = build(:profile_headshot, category: '')
      expect(headshot).to be_valid
    end
  end

  describe 'constants' do
    it 'defines CATEGORIES' do
      expect(described_class::CATEGORIES).to include('theatrical', 'commercial', 'character')
    end
  end

  describe 'scopes' do
    describe '.primary' do
      it 'returns only primary headshots' do
        person = create(:person)
        primary = create(:profile_headshot, profileable: person, is_primary: true)
        secondary = create(:profile_headshot, profileable: person, is_primary: false)

        expect(described_class.primary).to include(primary)
        expect(described_class.primary).not_to include(secondary)
      end
    end

    describe 'default_scope' do
      it 'orders by position' do
        person = create(:person)
        third = create(:profile_headshot, profileable: person, position: 2)
        first = create(:profile_headshot, profileable: person, position: 0)
        second = create(:profile_headshot, profileable: person, position: 1)

        expect(person.profile_headshots.to_a).to eq([ first, second, third ])
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default position on create' do
        person = create(:person)
        headshot = build(:profile_headshot, profileable: person, position: nil)
        headshot.valid?
        expect(headshot.position).to eq(0)
      end

      it 'increments position based on existing headshots' do
        person = create(:person)
        create(:profile_headshot, profileable: person, position: 0)
        headshot = build(:profile_headshot, profileable: person, position: nil)
        headshot.valid?
        expect(headshot.position).to eq(1)
      end
    end

    describe 'after_create' do
      it 'sets as primary if first headshot' do
        person = create(:person)
        headshot = create(:profile_headshot, profileable: person, is_primary: false)
        expect(headshot.reload.is_primary).to be true
      end
    end
  end

  describe '#safe_image_variant' do
    it 'returns nil when image is not attached' do
      headshot = build(:profile_headshot)
      expect(headshot.safe_image_variant(:thumb)).to be_nil
    end
  end
end
