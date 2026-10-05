# frozen_string_literal: true

# On the 1st: a statement for last month for every organization that had any
# money activity in it.
class MonthlyStatementsJob < ApplicationJob
  queue_as :background

  def perform(month_iso = nil)
    month = month_iso ? Date.iso8601(month_iso) : Date.current.prev_month.beginning_of_month
    Organization.find_each do |organization|
      next unless OrgStatementBuilder.activity?(organization, month)

      OrgStatementJob.perform_later(organization.id, month.iso8601)
    end
  end
end
