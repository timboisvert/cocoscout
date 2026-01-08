# frozen_string_literal: true

# Runs every minute to update sign-up form instance statuses based on time.
# This ensures status transitions happen reliably without relying on on-the-fly calculations.
#
# Status transitions:
#   initializing -> scheduled (when opens_at is in the future)
#   initializing -> open (when opens_at is nil or in the past)
#   scheduled -> open (when opens_at is reached)
#   open -> closed (when closes_at is reached)
#
class UpdateSignUpStatusesJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current

    # Track stats for logging
    stats = { initialized: 0, opened: 0, closed: 0 }

    # Process all instances that might need status updates
    SignUpFormInstance.needs_status_update.find_each do |instance|
      new_status = calculate_status(instance, now)

      if new_status != instance.status
        old_status = instance.status
        instance.update_column(:status, new_status)

        case new_status
        when "open" then stats[:opened] += 1
        when "closed" then stats[:closed] += 1
        when "scheduled" then stats[:initialized] += 1
        end

        Rails.logger.info "[SignUpStatus] Instance #{instance.id} transitioned from '#{old_status}' to '#{new_status}'"
      end
    end

    # Also close any that passed their closes_at but are still marked open
    closed_count = close_expired_instances(now)
    stats[:closed] += closed_count

    if stats.values.any?(&:positive?)
      Rails.logger.info "[SignUpStatus] Job completed: #{stats.inspect}"
    end
  end

  private

  def calculate_status(instance, now)
    # Cancelled takes precedence - don't change it
    return "cancelled" if instance.cancelled?

    # Check if closed
    if instance.closes_at.present? && instance.closes_at <= now
      return "closed"
    end

    # Determine the effective opens_at time
    # For fixed schedule mode, use the form's opens_at if instance's is nil
    effective_opens_at = instance.opens_at
    if effective_opens_at.nil? && instance.sign_up_form&.schedule_mode == "fixed"
      effective_opens_at = instance.sign_up_form.opens_at
    end

    # Check if should be open (opens_at passed or not set)
    if effective_opens_at.nil? || effective_opens_at <= now
      return "open"
    end

    # Opens_at is in the future
    "scheduled"
  end

  def close_expired_instances(now)
    # Find instances that are open but should be closed
    SignUpFormInstance
      .where(status: "open")
      .where("closes_at IS NOT NULL AND closes_at <= ?", now)
      .update_all(status: "closed")
  end
end
