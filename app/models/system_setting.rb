# frozen_string_literal: true

# SystemSetting stores key-value configuration that can be edited at runtime.
# Used for things like default templates, feature flags, etc.
#
class SystemSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Get a setting value by key, with optional default
  def self.get(key, default = nil)
    find_by(key: key)&.value || default
  end

  # Set a setting value by key
  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.save!
    setting
  end
end
