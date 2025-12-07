# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuestionTypes::YesnoType do
  describe '.key' do
    it 'returns the correct key' do
      expect(QuestionTypes::YesnoType.key).to eq('yesno')
    end
  end

  describe '.label' do
    it 'returns the correct label' do
      expect(QuestionTypes::YesnoType.label).to eq('Yes/No')
    end
  end

  describe '.needs_options?' do
    it 'returns false' do
      expect(QuestionTypes::YesnoType.needs_options?).to be false
    end
  end

  describe '.parse_answer_value' do
    it 'returns "yes" in an array' do
      expect(QuestionTypes::YesnoType.parse_answer_value('yes')).to eq([ 'yes' ])
    end

    it 'returns "no" in an array' do
      expect(QuestionTypes::YesnoType.parse_answer_value('no')).to eq([ 'no' ])
    end
  end

  describe 'registration' do
    it 'is registered in the base registry' do
      expect(QuestionTypes::Base.find('yesno')).to eq(QuestionTypes::YesnoType)
    end
  end
end
