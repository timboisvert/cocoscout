# frozen_string_literal: true

class TicketSyncJob < ApplicationJob
  queue_as :default

  def perform
    # Find all sync rules that are due
    due_rules = TicketSyncRule.due

    Rails.logger.info "[TicketSyncJob] Found #{due_rules.count} sync rules due for execution"

    due_rules.find_each do |rule|
      execute_rule(rule)
    end
  end

  private

  def execute_rule(rule)
    Rails.logger.info "[TicketSyncJob] Executing rule: #{rule.name} (#{rule.id})"

    rule.execute!

    Rails.logger.info "[TicketSyncJob] Completed rule: #{rule.name}"
  rescue StandardError => e
    Rails.logger.error "[TicketSyncJob] Error executing rule #{rule.id}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
  end
end
