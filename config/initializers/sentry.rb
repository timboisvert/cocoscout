# frozen_string_literal: true

Sentry.init do |config|
  config.enabled_environments = %w[production]
  config.breadcrumbs_logger = %i[active_support_logger http_logger]
  config.dsn = ENV["SENTRY_DSN"]
  config.traces_sample_rate = 0.5
  config.profiles_sample_rate = 0.5
  config.send_default_pii = true
  config.enable_logs = true
  config.enabled_patches = [ :logger ]

  # Filter out N+1 queries from solid_cache - these are expected behavior
  # for fragment caching with a database-backed cache store
  config.before_send = lambda do |event, hint|
    # Check if this is an N+1 query issue related to solid_cache
    if event.message&.include?("solid_cache_entries") ||
       event.fingerprint&.any? { |f| f.to_s.include?("solid_cache_entries") }
      return nil
    end

    # Also check in exception values
    if event.exception&.values&.any? { |e| e.value&.include?("solid_cache_entries") }
      return nil
    end

    event
  end
end
