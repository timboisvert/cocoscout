# frozen_string_literal: true

# How much mail CocoScout sends against its Mailgun plan (Tim, 2026-11-17:
# "something on the business side of superadmin that lets me know when I'm
# getting close to Mailgun's limit ... and when we're getting close to
# needing to upgrade again").
#
# Every email is counted as it goes out (MailVolumeObserver), one per
# recipient, into the month's row. CocoScout can count what it sends, not
# what Mailgun bills, so the plan's size is a number set in Superadmin and
# changed when the plan changes:
#   plan_emails   what the plan includes a month (10,000 on Basic)
#   upgrade_at    the monthly volume past which the next plan up is cheaper
#                 than paying for the extra (about 21,000 from Basic)
# Follower email has its own ceiling inside that, FOLLOWERS_MONTHLY_CAP
# (FollowerEmailAllowance.platform_cap).
class MailVolume
  PLAN_KEY = "mailgun_plan_emails"
  UPGRADE_KEY = "mailgun_upgrade_at"
  DEFAULT_PLAN_EMAILS = 10_000
  DEFAULT_UPGRADE_AT = 21_000
  # "Close" is this share of the plan, sent so far this month.
  CLOSE_AT = 0.8
  # A month's pace means little in its first days.
  PACE_FROM_DAY = 5

  class << self
    # One more email out, to this many people.
    def count!(recipients = 1, at: Time.current)
      return if recipients.to_i <= 0

      month = at.to_date.beginning_of_month
      MailVolumeMonth.upsert({ month: month, sent: recipients.to_i, counted_from: at, created_at: at, updated_at: at },
                             unique_by: :month, on_duplicate: Arel.sql("sent = mail_volume_months.sent + EXCLUDED.sent, updated_at = EXCLUDED.updated_at"))
    end

    def plan_emails = SystemSetting.get(PLAN_KEY).presence&.to_i || DEFAULT_PLAN_EMAILS
    def upgrade_at = SystemSetting.get(UPGRADE_KEY).presence&.to_i || DEFAULT_UPGRADE_AT

    def set!(plan_emails:, upgrade_at:)
      SystemSetting.set(PLAN_KEY, plan_emails.to_i.to_s) if plan_emails.to_i.positive?
      SystemSetting.set(UPGRADE_KEY, upgrade_at.to_i.to_s) if upgrade_at.to_i.positive?
    end

    # The daily look: superadmins are notified once a month when the month
    # gets close to the plan, and once when its pace says it's time to move
    # up a plan.
    def check!(now: Time.current)
      volume = new(now.to_date)
      SuperadminNotices.mail_volume_close(volume) if volume.close?
      SuperadminNotices.mail_upgrade_near(volume) if volume.upgrade_near?
    end
  end

  attr_reader :month

  def initialize(date = Date.current)
    @today = date.to_date
    @month = @today.beginning_of_month
  end

  def record = @record ||= MailVolumeMonth.find_by(month: month)
  def sent = record&.sent.to_i
  def counted_from = record&.counted_from
  def plan_emails = self.class.plan_emails
  def upgrade_at = self.class.upgrade_at
  def percent = plan_emails.positive? ? (sent * 100.0 / plan_emails).round : 0
  def left = [ plan_emails - sent, 0 ].max

  # Email to followers this month, every organization, and its ceiling.
  def follower_sent = @follower_sent ||= FollowerEmailAllowance.platform_used(month: month)
  def follower_cap = FollowerEmailAllowance.platform_cap
  def other_sent = [ sent - follower_sent, 0 ].max

  # Where the month is heading at the pace so far, from the day counting
  # began (the first month starts part way through). Nil in a month's first
  # days, when a pace says nothing yet.
  def projected
    return nil unless record && current_month?

    started = [ counted_from&.to_date || month, month ].max
    days = (@today - started).to_i + 1
    return nil if days < PACE_FROM_DAY

    (sent.to_f / days * month.end_of_month.day).round
  end

  def close? = current_month? && sent >= plan_emails * CLOSE_AT
  def upgrade_near? = projected.present? && projected >= upgrade_at

  # Extra emails organizations have paid for and not sent yet: mail still to
  # come that no month's count holds.
  def paid_unused
    @paid_unused ||= [ FollowerEmailBlock.sum(:emails) - FollowerEmail.sum(:paid_emails_used), 0 ].max
  end

  def blocks_this_month = FollowerEmailBlock.bought_in(month)

  private

  def current_month? = month == Date.current.beginning_of_month
end
