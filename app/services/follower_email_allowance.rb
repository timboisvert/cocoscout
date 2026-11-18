# frozen_string_literal: true

# How many emails to followers a Pro organization can still send. Pro
# includes 500 a month (Tim, 2026-10-23), used first and gone at the end of
# the month. Beyond that the organization buys blocks of 1,000 for $3
# (FollowerEmailBlock; Tim, 2026-11-17): what a block paid for carries over
# until it's used, for as long as the organization is on Pro. A send that
# needs more than both together offers the blocks it would take.
class FollowerEmailAllowance
  INCLUDED_PER_MONTH = 500

  def initialize(organization, month: Date.current)
    @organization = organization
    @month = month
  end

  def included = INCLUDED_PER_MONTH

  # Every email it sent this month, from the included ones and from blocks.
  def sent
    @sent ||= FollowerEmailDelivery.joins(:follower_email)
                                   .where(follower_emails: { organization_id: @organization.id })
                                   .where(sent_at: range)
                                   .count
  end

  # This month's emails that came out of paid blocks.
  def paid_used_this_month
    @paid_used_this_month ||= @organization.follower_emails.where(sent_at: range).sum(:paid_emails_used)
  end

  # Of the month's included emails, how many are used.
  def used = [ [ sent - paid_used_this_month, 0 ].max, included ].min
  def free_left = [ included - used, 0 ].max

  # Paid emails not used yet, from every block it ever bought. Frozen while
  # the organization isn't on Pro (it can't send then anyway); they come
  # back when it is again.
  def paid_left
    return 0 unless @organization.feature_available?(:mailing_lists)

    @paid_left ||= [ @organization.follower_email_blocks.sum(:emails) - @organization.follower_emails.sum(:paid_emails_used), 0 ].max
  end

  def left = free_left + paid_left
  def percent_used = [ (used * 100.0 / included).round, 100 ].min
  def allows?(count) = count <= left
  def resets_on = @month.next_month.beginning_of_month

  # How many blocks a send of this size would need on top of what's left.
  def blocks_needed(count)
    allows?(count) ? 0 : ((count - left) / FollowerEmailBlock::EMAILS.to_f).ceil
  end

  # Of a send this size, how many emails come out of paid blocks: the
  # month's included ones go first.
  def paid_part(count) = [ count - free_left, 0 ].max

  # "310 left this month and 70 paid for", for the send screen.
  def left_words
    free = "#{ActiveSupport::NumberHelper.number_to_delimited(free_left)} left this month"
    paid_left.positive? ? "#{free} and #{ActiveSupport::NumberHelper.number_to_delimited(paid_left)} more that you've paid for" : free
  end

  # All of CocoScout's emails to followers this month, every organization,
  # queued ones too. While follower email shares cocoscout.com's sending
  # domain and Mailgun plan with sign-in and ticket mail (FOLLOWERS_SENDING=on,
  # no FOLLOWERS_MAIL_DOMAIN; Tim, 2026-10-28), this cap keeps it from
  # crowding them out. FOLLOWERS_MONTHLY_CAP sets it; 2,000 unless set.
  PLATFORM_CAP_DEFAULT = 2_000

  def self.platform_cap
    ENV["FOLLOWERS_MONTHLY_CAP"].presence&.to_i || PLATFORM_CAP_DEFAULT
  end

  private

  def range = @month.beginning_of_month.beginning_of_day..@month.end_of_month.end_of_day

  public

  def self.platform_used(month: Date.current)
    FollowerEmailDelivery.where(created_at: month.beginning_of_month.beginning_of_day..month.end_of_month.end_of_day).count
  end

  def self.platform_allows?(count, month: Date.current)
    platform_used(month: month) + count <= platform_cap
  end
end
