# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Question, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      question = build(:question)
      expect(question).to be_valid
    end

    it 'is invalid without text' do
      question = build(:question, text: nil)
      expect(question).not_to be_valid
      expect(question.errors[:text]).to include("can't be blank")
    end

    it 'is invalid without question_type' do
      question = build(:question, question_type: nil)
      expect(question).not_to be_valid
      expect(question.errors[:question_type]).to include("can't be blank")
    end
  end

  describe 'associations' do
    it 'belongs to questionable' do
      question = create(:question)
      expect(question.questionable).to be_present
      expect(question).to respond_to(:questionable)
    end

    it 'has many question_options' do
      question = create(:question)
      expect(question).to respond_to(:question_options)
    end

    it 'has many answers' do
      question = create(:question)
      expect(question).to respond_to(:answers)
    end
  end

  describe 'nested attributes' do
    it 'accepts nested attributes for question_options' do
      audition_cycle = create(:audition_cycle)
      question = audition_cycle.questions.create(
        text: 'What is your favorite color?',
        question_type: 'multiple_choice',
        question_options_attributes: [
          { text: 'Red' },
          { text: 'Blue' },
          { text: 'Green' }
        ]
      )

      expect(question.question_options.count).to eq(3)
      expect(question.question_options.pluck(:text)).to match_array(%w[Red Blue Green])
    end

    it 'allows destroying question_options' do
      question = create(:question, :multiple_choice)
      option = create(:question_option, question: question)

      question.update(question_options_attributes: [ { id: option.id, _destroy: true } ])

      expect(question.question_options.count).to eq(0)
    end
  end

  describe 'required field' do
    it 'can be set to required' do
      question = create(:question, :required)
      expect(question.required).to be true
    end

    it 'defaults to not required' do
      question = create(:question)
      expect(question.required).to be false
    end
  end

  describe 'question types' do
    it 'can be short_text' do
      question = create(:question, question_type: 'short_text')
      expect(question.question_type).to eq('short_text')
    end

    it 'can be long_text' do
      question = create(:question, :long_text)
      expect(question.question_type).to eq('long_text')
    end

    it 'can be multiple_choice' do
      question = create(:question, :multiple_choice)
      expect(question.question_type).to eq('multiple_choice')
    end
  end

  describe 'polymorphic questionable' do
    it 'can belong to a AuditionCycle' do
      audition_cycle = create(:audition_cycle)
      question = create(:question, questionable: audition_cycle)

      expect(question.questionable).to eq(audition_cycle)
      expect(question.questionable_type).to eq('AuditionCycle')
    end
  end

  describe '#question_type_class' do
    it 'returns the correct type class for text' do
      question = build(:question, question_type: 'text')
      expect(question.question_type_class).to eq(QuestionTypes::TextType)
    end

    it 'returns the correct type class for textarea' do
      question = build(:question, question_type: 'textarea')
      expect(question.question_type_class).to eq(QuestionTypes::TextareaType)
    end

    it 'returns the correct type class for yesno' do
      question = build(:question, question_type: 'yesno')
      expect(question.question_type_class).to eq(QuestionTypes::YesnoType)
    end

    it 'returns the correct type class for multiple-multiple' do
      question = build(:question, question_type: 'multiple-multiple')
      expect(question.question_type_class).to eq(QuestionTypes::MultipleMultipleType)
    end

    it 'returns the correct type class for multiple-single' do
      question = build(:question, question_type: 'multiple-single')
      expect(question.question_type_class).to eq(QuestionTypes::MultipleSingleType)
    end

    it 'returns nil for unknown type' do
      question = build(:question, question_type: 'unknown')
      expect(question.question_type_class).to be_nil
    end
  end

  describe 'question_options validation' do
    it 'is valid for multiple-multiple with options' do
      audition_cycle = create(:audition_cycle)
      question = audition_cycle.questions.build(
        text: 'Select your preferences',
        question_type: 'multiple-multiple',
        question_options_attributes: [ { text: 'Option 1' }, { text: 'Option 2' } ]
      )
      expect(question).to be_valid
    end

    it 'is invalid for multiple-multiple without options' do
      audition_cycle = create(:audition_cycle)
      question = audition_cycle.questions.build(
        text: 'Select your preferences',
        question_type: 'multiple-multiple'
      )
      expect(question).not_to be_valid
      expect(question.errors[:question_options]).to be_present
    end

    it 'is valid for text type without options' do
      question = build(:question, question_type: 'text')
      expect(question).to be_valid
    end
  end
end
