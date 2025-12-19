# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Audition, type: :model do
  describe 'associations' do
    it 'belongs to an auditionable (polymorphic)' do
      audition = Audition.new
      expect(audition).to respond_to(:auditionable)
    end

    it 'belongs to an audition_request' do
      audition = Audition.new
      expect(audition).to respond_to(:audition_request)
    end

    it 'belongs to an audition_session' do
      audition = Audition.new
      expect(audition).to respond_to(:audition_session)
    end

    it 'has many audition_votes' do
      audition = Audition.new
      expect(audition).to respond_to(:audition_votes)
    end
  end

  describe '#person' do
    it 'returns the auditionable when it is a Person' do
      person = create(:person)
      audition = Audition.new(auditionable: person)
      expect(audition.person).to eq(person)
    end

    it 'returns nil when auditionable is not a Person' do
      group = create(:group)
      audition = Audition.new(auditionable: group)
      expect(audition.person).to be_nil
    end
  end
end
