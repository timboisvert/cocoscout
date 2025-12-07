# frozen_string_literal: true

Sentry.init do |config|
  config.enabled_environments = %w[production]
  config.breadcrumbs_logger = %i[active_support_logger http_logger]
  config.dsn = ENV["SENTRY_DSN"]
  config.traces_sample_rate = 0.1
  config.profiles_sample_rate = 0.1
  config.send_default_pii = true
  config.enable_logs = true
  config.enabled_patches = [ :logger ]
end
