# frozen_string_literal: true

class ExpenseCategories
  class << self
    def all
      @all ||= config["expense_categories"]
    end

    def keys
      all.keys
    end

    def options_for_select
      all.map { |key, data| [ data["label"], key ] }
    end

    def label_for(key)
      all.dig(key.to_s, "label") || key.to_s.titleize
    end

    def description_for(key)
      all.dig(key.to_s, "description")
    end

    def icon_for(key)
      all.dig(key.to_s, "icon") || "ellipsis-horizontal-circle"
    end

    private

    def config
      @config ||= YAML.load_file(Rails.root.join("config", "expense_categories.yml"))
    end
  end
end
