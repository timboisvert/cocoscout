# frozen_string_literal: true

# How many emails to followers a Pro organization has sent this month, against
# what Pro includes: 500 a month for now (Tim, 2026-10-23: "much lower for
# now"). It's a hard stop: a send that would go past it waits for next month.
# More (and paying for more) comes later.
class FollowerEmailAllowance
  INCLUDED_PER_MONTH = 500

  def initialize(organization, month: Date.current)
    @organization = organization
    @month = month
  end

  def included = INCLUDED_PER_MONTH

  def used
    @used ||= FollowerEmailDelivery.joins(:follower_email)
                                   .where(follower_emails: { organization_id: @organization.id })
                                   .where(sent_at: @month.beginning_of_month.beginning_of_day..@month.end_of_month.end_of_day)
                                   .count
  end

  def left = [ included - used, 0 ].max
  def over = [ used - included, 0 ].max
  def percent_used = [ (used * 100.0 / included).round, 100 ].min
  def allows?(count) = count <= left
  def resets_on = @month.next_month.beginning_of_month
end
