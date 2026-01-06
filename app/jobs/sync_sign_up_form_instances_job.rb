# frozen_string_literal: true

# Job to sync sign-up form instances for per_event forms
# This is a maintenance job that can be run manually to ensure consistency.
# Normally, instances are created automatically when shows are created (via Show callbacks).
#
# Usage:
#   SyncSignUpFormInstancesJob.perform_now                      # All productions
#   SyncSignUpFormInstancesJob.perform_now(production_id: 123)  # Specific production
#
class SyncSignUpFormInstancesJob < ApplicationJob
  queue_as :default

  # Run for all productions or a specific one
  def perform(production_id: nil)
    if production_id
      sync_production(Production.find(production_id))
    else
      Production.find_each do |production|
        sync_production(production)
      end
    end
  end

  private

  def sync_production(production)
    # Find all per_event sign-up forms that are active
    production.sign_up_forms.where(scope: "per_event", active: true).find_each do |form|
      sync_form_instances(form)
    end
  end

  def sync_form_instances(form)
    matching_shows = form.matching_shows

    created_count = 0
    matching_shows.each do |show|
      # Skip if instance already exists
      next if form.sign_up_form_instances.exists?(show_id: show.id)

      # Create instance for this show
      form.create_instance_for_show!(show)
      created_count += 1
      Rails.logger.info "[SyncSignUpFormInstancesJob] Created instance for SignUpForm##{form.id} and Show##{show.id}"
    rescue StandardError => e
      Rails.logger.error "[SyncSignUpFormInstancesJob] Failed to create instance for SignUpForm##{form.id} and Show##{show.id}: #{e.message}"
    end

    Rails.logger.info "[SyncSignUpFormInstancesJob] Created #{created_count} instances for SignUpForm##{form.id}" if created_count > 0
  end
end
