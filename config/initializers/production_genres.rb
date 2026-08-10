# frozen_string_literal: true

# Load production genres configuration (mirrors EventTypes / event_types.yml)
PRODUCTION_GENRES_CONFIG = YAML.load_file(Rails.root.join("config", "production_genres.yml")).freeze

# Helper module for accessing production genre configuration
module ProductionGenres
  def self.config
    PRODUCTION_GENRES_CONFIG["production_genres"]
  end

  def self.keys
    config.keys
  end

  def self.label(genre)
    config.dig(genre.to_s, "label")
  end

  def self.description(genre)
    config.dig(genre.to_s, "description")
  end

  # "team", "showcase", "production", … — used for copy like
  # "What's your team called?"
  def self.noun(genre)
    config.dig(genre.to_s, "noun") || "production"
  end

  def self.name_placeholder(genre)
    config.dig(genre.to_s, "name_placeholder")
  end

  # [{ "name" => ..., "quantity" => ..., "category" => ... }, ...]
  def self.role_presets(genre)
    config.dig(genre.to_s, "role_presets") || []
  end
end
