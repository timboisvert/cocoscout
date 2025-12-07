# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuestionTypes::Base do
  describe '.registry' do
    it 'returns a hash of registered types' do
      expect(QuestionTypes::Base.registry).to be_a(Hash)
      expect(QuestionTypes::Base.registry).not_to be_empty
    end

    it 'includes all defined question types' do
      expect(QuestionTypes::Base.registry.keys).to include('text', 'textarea', 'yesno', 'multiple-multiple',
                                                           'multiple-single')
    end
  end

  describe '.register' do
    it 'adds a type to the registry' do
      # Save original registry state
      QuestionTypes::Base.registry.keys.dup

      test_class = Class.new(QuestionTypes::Base) do
        def self.key
          'test'
        end
      end
      QuestionTypes::Base.register('test', test_class)

      expect(QuestionTypes::Base.registry['test']).to eq(test_class)

      # Clean up
      QuestionTypes::Base.registry.delete('test')
    end
  end

  describe '.all_types' do
    it 'returns all registered type classes' do
      types = QuestionTypes::Base.all_types
      expect(types).to be_an(Array)
      # Should have at least our 5 standard types
      expect(types.length).to be >= 5
      # Check that all standard types are present
      expect(types).to include(
        QuestionTypes::TextType,
        QuestionTypes::TextareaType,
        QuestionTypes::YesnoType,
        QuestionTypes::MultipleMultipleType,
        QuestionTypes::MultipleSingleType
      )
    end

    it 'returns types sorted by key' do
      # Test that sorting works correctly by checking specific types
      types = QuestionTypes::Base.all_types
      keys = types.map(&:key)

      # Find positions of our standard types
      multiple_multiple_pos = keys.index('multiple-multiple')
      text_pos = keys.index('text')

      # multiple-multiple should come before text alphabetically
      expect(multiple_multiple_pos).to be < text_pos
    end
  end

  describe '.find' do
    it 'finds a type by key' do
      expect(QuestionTypes::Base.find('text')).to eq(QuestionTypes::TextType)
      expect(QuestionTypes::Base.find('textarea')).to eq(QuestionTypes::TextareaType)
    end

    it 'returns nil for unknown type' do
      expect(QuestionTypes::Base.find('unknown')).to be_nil
    end
  end

  describe 'abstract methods' do
    it 'raises NotImplementedError for key' do
      expect { QuestionTypes::Base.key }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for label' do
      expect { QuestionTypes::Base.label }.to raise_error(NotImplementedError)
    end

    it 'has default implementation for needs_options?' do
      expect(QuestionTypes::Base.needs_options?).to be false
    end

    it 'has default implementation for parse_answer_value' do
      expect(QuestionTypes::Base.parse_answer_value('test')).to eq([ 'test' ])
    end
  end
end
