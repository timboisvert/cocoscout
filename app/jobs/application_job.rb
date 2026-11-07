# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # A job for one organization's records runs in that organization's time
  # zone (TimeZones.of reads it off the arguments), so the dates it computes
  # and the times it renders are the organization's. A job that walks every
  # organization picks the zone itself, per organization.
  around_perform do |job, block|
    TimeZones.use(TimeZones.of(*job.arguments), &block)
  end
end
