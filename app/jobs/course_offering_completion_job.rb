# frozen_string_literal: true

# Runs daily (configured in recurring.yml). Auto-completes course runs that are
# over: registration closed AND every session in the past. A completed run drops
# out of the "Active courses" count and into the Completed section, so finished,
# paid-out courses stop showing as active. Course PRODUCTIONS are never archived
# here — they're durable and reused across runs (see ContractCompletionJob, which
# also skips course productions).
class CourseOfferingCompletionJob < ApplicationJob
  queue_as :default

  def perform
    completed = 0

    CourseOffering.where(status: "closed").find_each do |offering|
      last_session = offering.sessions.maximum(:date_and_time)
      next if last_session.nil? || last_session >= Time.current

      offering.update!(status: :completed)
      completed += 1
      Rails.logger.info "[CourseOfferingCompletionJob] Completed offering #{offering.id} (#{offering.title})"
    end

    Rails.logger.info "[CourseOfferingCompletionJob] Completed #{completed} course run(s)"
  end
end
