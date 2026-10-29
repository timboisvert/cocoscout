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

  # All of CocoScout's emails to followers this month, every organization,
  # queued ones too. While follower email shares cocoscout.com's sending
  # domain and Mailgun plan with sign-in and ticket mail (FOLLOWERS_SENDING=on,
  # no FOLLOWERS_MAIL_DOMAIN; Tim, 2026-10-28), this cap keeps it from
  # crowding them out. FOLLOWERS_MONTHLY_CAP sets it; 2,000 unless set.
  PLATFORM_CAP_DEFAULT = 2_000

  def self.platform_cap
    ENV["FOLLOWERS_MONTHLY_CAP"].presence&.to_i || PLATFORM_CAP_DEFAULT
  end

  def self.platform_used(month: Date.current)
    FollowerEmailDelivery.where(created_at: month.beginning_of_month.beginning_of_day..month.end_of_month.end_of_day).count
  end

  def self.platform_allows?(count, month: Date.current)
    platform_used(month: month) + count <= platform_cap
  end
end
