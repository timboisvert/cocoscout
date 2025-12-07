# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Answer, type: :model do
  describe 'associations' do
    it 'belongs to question' do
      answer = create(:answer)
      expect(answer.question).to be_present
      expect(answer).to respond_to(:question)
    end

    it 'belongs to audition_request' do
      answer = create(:answer)
      expect(answer.audition_request).to be_present
      expect(answer).to respond_to(:audition_request)
    end
  end

  describe 'creating answers' do
    it 'can be created with value' do
      audition_request = create(:audition_request)
      question = create(:question, questionable: audition_request.audition_cycle)
      answer = Answer.create(
        audition_request: audition_request,
        question: question,
        value: 'My answer text'
      )

      expect(answer.value).to eq('My answer text')
      expect(answer.question).to eq(question)
      expect(answer.audition_request).to eq(audition_request)
    end
  end

  describe 'answer types' do
    let(:audition_request) { create(:audition_request) }

    it 'can store short text answers' do
      question = create(:question, question_type: 'short_text', questionable: audition_request.audition_cycle)
      answer = create(:answer, question: question, audition_request: audition_request, value: 'Short answer')

      expect(answer.value).to eq('Short answer')
    end

    it 'can store long text answers' do
      question = create(:question, :long_text, questionable: audition_request.audition_cycle)
      answer = create(:answer, question: question, audition_request: audition_request,
                               value: 'This is a much longer answer with multiple sentences.')

      expect(answer.value).to eq('This is a much longer answer with multiple sentences.')
    end
  end

  describe '#value_as_array' do
    let(:audition_request) { create(:audition_request) }

    it 'returns single value in array for text type' do
      question = create(:question, question_type: 'text', questionable: audition_request.audition_cycle)
      answer = create(:answer, question: question, audition_request: audition_request, value: 'Test answer')

      expect(answer.value_as_array).to eq([ 'Test answer' ])
    end

    it 'returns single value in array for yesno type' do
      question = create(:question, question_type: 'yesno', questionable: audition_request.audition_cycle)
      answer = create(:answer, question: question, audition_request: audition_request, value: 'yes')

      expect(answer.value_as_array).to eq([ 'yes' ])
    end

    it 'parses multiple-multiple answers correctly' do
      audition_cycle = audition_request.audition_cycle
      question = audition_cycle.questions.create!(
        text: 'Select options',
        question_type: 'multiple-multiple',
        question_options_attributes: [
          { text: 'Option 1' },
          { text: 'Option 2' }
        ]
      )
      answer = create(:answer, question: question, audition_request: audition_request,
                               value: '{"Option 1":"Option 1", "Option 2":"Option 2"}')

      expect(answer.value_as_array).to match_array([ 'Option 1', 'Option 2' ])
    end

    it 'handles invalid JSON gracefully for multiple-multiple' do
      audition_cycle = audition_request.audition_cycle
      question = audition_cycle.questions.create!(
        text: 'Select option',
        question_type: 'multiple-multiple',
        question_options_attributes: [ { text: 'Option 1' } ]
      )
      answer = create(:answer, question: question, audition_request: audition_request, value: 'invalid json')

      expect(answer.value_as_array).to eq([])
    end
  end
end
