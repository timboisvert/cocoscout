# frozen_string_literal: true

# Load event types configuration
EVENT_TYPES_CONFIG = YAML.load_file(Rails.root.join("config", "event_types.yml")).freeze

# Helper module for accessing event types configuration
module EventTypes
  def self.config
    EVENT_TYPES_CONFIG["event_types"]
  end

  def self.all
    config.keys
  end

  def self.enum_hash
    config.keys.each_with_object({}) { |k, h| h[k.to_sym] = k }
  end

  def self.labels
    config.transform_values { |v| v["label"] }
  end

  def self.for_select
    config.map { |key, value| [ value["label"], key ] }
  end

  def self.casting_enabled_default(event_type)
    config.dig(event_type.to_s, "casting_enabled_default") || false
  end

  def self.public_visible_default(event_type)
    config.dig(event_type.to_s, "public_visible_default") || false
  end

  def self.call_time_enabled_default(event_type)
    config.dig(event_type.to_s, "call_time_enabled_default") || false
  end

  def self.casting_enabled_defaults
    config.select { |_, v| v["casting_enabled_default"] == true }.keys
  end

  def self.casting_disabled_defaults
    config.select { |_, v| v["casting_enabled_default"] == false }.keys
  end

  def self.revenue_event_default(event_type)
    config.dig(event_type.to_s, "revenue_event") || false
  end

  def self.revenue_event_types
    config.select { |_, v| v["revenue_event"] == true }.keys
  end

  def self.non_revenue_event_types
    config.select { |_, v| v["revenue_event"] == false }.keys
  end
end
