# frozen_string_literal: true

# Configure Active Record encryption keys
# In production, these should be set via Rails credentials or environment variables
# For development, we use static keys (these are NOT secret - development only)

if Rails.env.development? || Rails.env.test?
  Rails.application.config.active_record.encryption.primary_key = ENV.fetch(
    "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",
    "WIAHbGCBl9i1eEAli5q22G1mdSl7XXjO"
  )
  Rails.application.config.active_record.encryption.deterministic_key = ENV.fetch(
    "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",
    "MvEIz37OXUH7b7d3JMycK2cQscdofIBk"
  )
  Rails.application.config.active_record.encryption.key_derivation_salt = ENV.fetch(
    "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT",
    "Rxmnk3TKC7T6skjyWyNdqMo9aU5n9QFf"
  )
end
