# frozen_string_literal: true

# Org-level payout cadence: how often the org automatically runs a payout batch
# (paying everyone with a connected bank and a positive balance) instead of
# clicking "Run payout" by hand.
module PayoutScheduling
  extend ActiveSupport::Concern

  SCHEDULES = %w[manual weekly monthly].freeze
  FUNDING_METHODS = %w[ach card].freeze
  DEFAULT_WEEKLY_DAY = 5  # Friday
  DEFAULT_MONTHLY_DAY = 1

  included do
    validates :payout_schedule, inclusion: { in: SCHEDULES }
    validates :payout_funding_method, inclusion: { in: FUNDING_METHODS }
  end

  def payout_schedule_enabled?
    payout_schedule.present? && payout_schedule != "manual"
  end

  # The next date a scheduled payout will run on/after `from` (nil when manual).
  def next_payout_date(from: Date.current)
    return nil unless payout_schedule_enabled?

    case payout_schedule
    when "weekly"
      day = (payout_schedule_day || DEFAULT_WEEKLY_DAY) % 7
      from + ((day - from.wday) % 7)
    when "monthly"
      monthly_candidate(from) || monthly_candidate(from.next_month.beginning_of_month)
    end
  end

  # Should a scheduled run happen today (and hasn't already)?
  def due_for_scheduled_payout?(on: Date.current)
    payout_schedule_enabled? && next_payout_date(from: on) == on && last_auto_payout_on != on
  end

  def payout_schedule_label
    case payout_schedule
    when "weekly"  then "Weekly on #{Date::DAYNAMES[(payout_schedule_day || DEFAULT_WEEKLY_DAY) % 7]}s"
    when "monthly" then "Monthly on the #{(payout_schedule_day || DEFAULT_MONTHLY_DAY).ordinalize}"
    else "Manual — run payouts yourself"
    end
  end

  private

  # The monthly payout date within the month containing `from`, or nil if that
  # date has already passed this month.
  def monthly_candidate(from)
    dom = payout_schedule_day || DEFAULT_MONTHLY_DAY
    target = [ dom, from.end_of_month.day ].min
    candidate = from.change(day: target)
    candidate >= from ? candidate : nil
  end
end
