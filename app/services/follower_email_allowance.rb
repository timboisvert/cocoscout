# frozen_string_literal: true

# How many emails to followers a Pro organization has sent this month, against
# what Pro includes. Past it, extra emails are billed per thousand once Tim
# sets the price (OVERAGE_CENTS_PER_THOUSAND); until then, nothing extra is
# charged.
class FollowerEmailAllowance
  INCLUDED_PER_MONTH = 10_000
  OVERAGE_CENTS_PER_THOUSAND = nil

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
  def resets_on = @month.next_month.beginning_of_month
end
