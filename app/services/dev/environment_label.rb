# frozen_string_literal: true

module Dev
  # What the dev indicator says (Tim, 2026-11-01): there is no staging, only
  # production and dev, so dev must never be mistaken for production. Nil in
  # every other environment, so production renders nothing.
  #
  # Once dev has been seeded from production (bin/seed_dev_from_prod), it says
  # so and names the day, read once per process from ar_internal_metadata,
  # where Dev::ProdCopyScrubber writes it.
  module EnvironmentLabel
    module_function

    def text
      return nil unless Rails.env.development?

      copied = seeded_on
      copied ? "Dev · production data from #{copied}" : "Dev"
    end

    def title_prefix
      Rails.env.development? ? "[DEV] " : ""
    end

    def seeded_on
      return @seeded_on if defined?(@seeded_on)

      @seeded_on = begin
        value = ActiveRecord::Base.connection.select_value("SELECT value FROM ar_internal_metadata WHERE key = 'seeded_from_production_on'")
        value.present? ? Date.parse(value).strftime("%b %-d") : nil
      rescue StandardError
        nil
      end
    end
  end
end
