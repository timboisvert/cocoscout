# frozen_string_literal: true

class AutopilotPayrollJob < ApplicationJob
  queue_as :default

  # This job runs every 5 minutes (configured in recurring.yml)
  # It checks all organizations with autopilot enabled and creates
  # payroll runs when a period has ended.
  def perform
    PayrollSchedule.where(autopilot: true).find_each do |schedule|
      create_run_if_period_ended(schedule)
    end
  end

  private

  def create_run_if_period_ended(schedule)
    current_period = schedule.current_period
    return unless current_period

    period_end = current_period[:end]
    
    # Only create a run if the period has ended
    return unless Time.current > period_end.end_of_day

    # Check if a run already exists for this period
    existing_run = schedule.organization.payroll_runs
      .where(period_start: current_period[:start], period_end: period_end)
      .exists?
    
    return if existing_run

    # Create the payroll run
    run = schedule.organization.payroll_runs.create!(
      period_start: current_period[:start],
      period_end: period_end,
      notes: "Auto-created by Autopilot"
    )

    run.build_line_items!

    Rails.logger.info "[AutopilotPayroll] Created run #{run.id} for #{schedule.organization.name} (#{current_period[:start]} - #{period_end})"
  rescue StandardError => e
    Rails.logger.error "[AutopilotPayroll] Error creating run for schedule #{schedule.id}: #{e.message}"
  end
end
