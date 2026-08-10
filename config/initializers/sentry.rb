# frozen_string_literal: true

Sentry.init do |config|
  config.enabled_environments = %w[production]
  config.breadcrumbs_logger = %i[active_support_logger http_logger]
  config.dsn = ENV["SENTRY_DSN"]
  config.send_default_pii = true
  # Performance monitoring is off: no traces_sample_rate, so no profiling
  # either (profiles only sample within a trace). We measure query cost with
  # prosopite in development and query-count specs in the suite, not from
  # sampled production traces. Errors and breadcrumbs are unaffected.
  # Sentry Logs product disabled: forwarding every Rails.logger call to Sentry
  # was burning through the 5GB monthly logs budget by day ~22. Errors,
  # breadcrumbs, and performance traces still flow normally — only the
  # structured "Logs" tab is turned off. Rails logs still go to their usual
  # destination.
  config.enable_logs = false

  # There was a before_send here muting N+1 events that mentioned
  # solid_cache_entries. With performance monitoring off it had no N+1 events
  # left to mute — and its last branch matched on exception values, so it would
  # have gone on silently dropping real errors that happened to name that table.
end
