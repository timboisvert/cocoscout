# frozen_string_literal: true

module Dev
  # What the dev indicator says (Tim, 2026-11-01): there is no staging, only
  # production and dev, so dev must never be mistaken for production. Nil in
  # every other environment, so production renders nothing.
  #
  # On a scrubbed copy of production (bin/prod_copy), it names the copy and the
  # day it was taken, read once per process from ar_internal_metadata, where
  # Dev::ProdCopyScrubber writes it.
  module EnvironmentLabel
    module_function

    def text
      return nil unless Rails.env.development?

      copied = prod_copy_from
      copied ? "Dev · production copy #{copied}" : "Dev"
    end

    def title_prefix
      Rails.env.development? ? "[#{prod_copy_from ? 'DEV COPY' : 'DEV'}] " : ""
    end

    def prod_copy_from
      return @prod_copy_from if defined?(@prod_copy_from)

      @prod_copy_from = begin
        value = ActiveRecord::Base.connection.select_value("SELECT value FROM ar_internal_metadata WHERE key = 'prod_copy_from'")
        value.present? ? Date.parse(value).strftime("%b %-d") : nil
      rescue StandardError
        nil
      end
    end
  end
end
