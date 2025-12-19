# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Social, type: :model do
  describe 'associations' do
    it 'belongs to a sociable (polymorphic)' do
      social = Social.new
      expect(social).to respond_to(:sociable)
    end
  end

  describe 'validations' do
    it 'is invalid without a platform' do
      social = Social.new(platform: nil, handle: 'test')
      expect(social).not_to be_valid
      expect(social.errors[:platform]).to include("can't be blank")
    end

    it 'is invalid without a handle' do
      social = Social.new(platform: :instagram, handle: nil)
      expect(social).not_to be_valid
      expect(social.errors[:handle]).to include("can't be blank")
    end

    it 'requires a name for website platform' do
      person = create(:person)
      social = Social.new(sociable: person, platform: :website, handle: 'example.com', name: nil)
      expect(social).not_to be_valid
      expect(social.errors[:name]).to include("can't be blank")
    end

    it 'requires a name for other platform' do
      person = create(:person)
      social = Social.new(sociable: person, platform: :other, handle: 'test', name: nil)
      expect(social).not_to be_valid
      expect(social.errors[:name]).to include("can't be blank")
    end

    it 'does not require name for standard platforms' do
      person = create(:person)
      social = Social.new(sociable: person, platform: :instagram, handle: 'testuser')
      expect(social).to be_valid
    end
  end

  describe 'enums' do
    it 'defines platform enum' do
      expect(described_class.platforms.keys).to include(
        'instagram', 'tiktok', 'x', 'facebook', 'youtube', 'linkedin', 'website', 'other'
      )
    end
  end

  describe '#display_name' do
    it 'returns the handle for standard platforms' do
      social = Social.new(platform: :instagram, handle: '@testuser')
      expect(social.display_name).to eq('@testuser')
    end

    it 'returns the name for website platform' do
      social = Social.new(platform: :website, handle: 'example.com', name: 'My Website')
      expect(social.display_name).to eq('My Website')
    end

    it 'returns handle if name is blank for website' do
      social = Social.new(platform: :website, handle: 'example.com', name: '')
      expect(social.display_name).to eq('example.com')
    end
  end

  describe '#url' do
    it 'returns nil when handle is blank' do
      social = Social.new(platform: :instagram, handle: nil)
      expect(social.url).to be_nil
    end

    it 'generates correct Instagram URL' do
      social = Social.new(platform: :instagram, handle: '@testuser')
      expect(social.url).to eq('https://instagram.com/testuser')
    end

    it 'generates correct Instagram URL without @ prefix' do
      social = Social.new(platform: :instagram, handle: 'testuser')
      expect(social.url).to eq('https://instagram.com/testuser')
    end

    it 'generates correct TikTok URL' do
      social = Social.new(platform: :tiktok, handle: 'testuser')
      expect(social.url).to eq('https://tiktok.com/@testuser')
    end

    it 'generates correct X URL' do
      social = Social.new(platform: :x, handle: '@testuser')
      expect(social.url).to eq('https://x.com/testuser')
    end

    it 'generates correct Facebook URL' do
      social = Social.new(platform: :facebook, handle: 'testuser')
      expect(social.url).to eq('https://facebook.com/testuser')
    end

    it 'generates correct YouTube URL' do
      social = Social.new(platform: :youtube, handle: '@testchannel')
      expect(social.url).to eq('https://youtube.com/testchannel')
    end

    it 'generates correct LinkedIn URL' do
      social = Social.new(platform: :linkedin, handle: 'testuser')
      expect(social.url).to eq('https://linkedin.com/in/testuser')
    end

    it 'generates correct website URL' do
      social = Social.new(platform: :website, handle: 'example.com')
      expect(social.url).to eq('https://example.com')
    end
  end

  describe 'callbacks' do
    describe '#normalize_handle' do
      it 'removes https:// prefix from website handles' do
        person = create(:person)
        social = Social.create!(sociable: person, platform: :website, handle: 'https://example.com', name: 'My Site')
        expect(social.handle).to eq('example.com')
      end

      it 'removes http:// prefix from website handles' do
        person = create(:person)
        social = Social.create!(sociable: person, platform: :website, handle: 'http://example.com', name: 'My Site')
        expect(social.handle).to eq('example.com')
      end

      it 'does not modify handles for other platforms' do
        person = create(:person)
        social = Social.create!(sociable: person, platform: :instagram, handle: '@testuser')
        expect(social.handle).to eq('@testuser')
      end
    end
  end
end
