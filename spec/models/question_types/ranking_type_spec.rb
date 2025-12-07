# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuestionTypes::RankingType do
  describe '.key' do
    it "returns 'ranking'" do
      expect(described_class.key).to eq('ranking')
    end
  end

  describe '.label' do
    it "returns 'Ranking'" do
      expect(described_class.label).to eq('Ranking')
    end
  end

  describe '.sort_order' do
    it 'returns 6' do
      expect(described_class.sort_order).to eq(6)
    end
  end

  describe '.needs_options?' do
    it 'returns true' do
      expect(described_class.needs_options?).to be true
    end
  end

  describe '.parse_answer_value' do
    it 'parses JSON array of ranked options' do
      value = '["Option A", "Option B", "Option C"]'
      result = described_class.parse_answer_value(value)
      expect(result).to eq([ 'Option A', 'Option B', 'Option C' ])
    end

    it 'returns empty array for invalid JSON' do
      value = 'invalid json'
      result = described_class.parse_answer_value(value)
      expect(result).to eq([])
    end

    it 'returns empty array for non-array JSON' do
      value = '{"key": "value"}'
      result = described_class.parse_answer_value(value)
      expect(result).to eq([])
    end

    it 'handles empty array' do
      value = '[]'
      result = described_class.parse_answer_value(value)
      expect(result).to eq([])
    end
  end
end
