# frozen_string_literal: true

module QuestionTypes
  class Base
    class << self
      # Registry to store all question type classes
      def registry
        @registry ||= {}
      end

      # Register a question type class
      def register(key, klass)
        registry[key.to_s] = klass
      end

      # Get all registered types in display order
      def all_types
        registry.values.sort_by(&:sort_order)
      end

      # Find a type class by key
      def find(key)
        registry[key.to_s]
      end
    end

    # Abstract methods to be implemented by subclasses
    def self.key
      raise NotImplementedError, "Subclasses must implement the 'key' method"
    end

    def self.label
      raise NotImplementedError, "Subclasses must implement the 'label' method"
    end

    def self.needs_options?
      false
    end

    def self.parse_answer_value(value)
      [ value ]
    end
  end
end
