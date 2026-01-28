# frozen_string_literal: true

class PayrollSchedule < ApplicationRecord
  PERIOD_TYPES = %w[weekly biweekly semi_monthly monthly].freeze
  PAYDAY_TIMINGS = %w[period_end next_business_day days_after].freeze
  SEMI_MONTHLY_OPTIONS = %w[1_and_16 15_and_last].freeze

  belongs_to :organization

  has_many :payroll_runs, dependent: :nullify

  validates :period_type, inclusion: { in: PERIOD_TYPES }
  validates :payday_timing, inclusion: { in: PAYDAY_TIMINGS }
  validates :payday_offset_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 14 },
            if: -> { payday_timing == "days_after" }
  validates :semi_monthly_days, inclusion: { in: SEMI_MONTHLY_OPTIONS }, if: :semi_monthly?

  scope :active, -> { where(active: true) }

  before_validation :set_defaults

  # Period type helpers
  def weekly?
    period_type == "weekly"
  end

  def biweekly?
    period_type == "biweekly"
  end

  def semi_monthly?
    period_type == "semi_monthly"
  end

  def monthly?
    period_type == "monthly"
  end

  # Description for display
  def period_type_label
    case period_type
    when "weekly" then "Weekly"
    when "biweekly" then "Every two weeks"
    when "semi_monthly" then "Twice a month"
    when "monthly" then "Monthly"
    else period_type.humanize
    end
  end

  def payday_timing_label
    case payday_timing
    when "period_end" then "On the last day of the period"
    when "next_business_day" then "Next business day after period ends"
    when "days_after" then "#{payday_offset_days} day#{"s" if payday_offset_days != 1} after period ends"
    else payday_timing.humanize
    end
  end

  def description
    "#{period_type_label}, #{payday_timing_label.downcase}"
  end

  # Calculate the current period based on today's date
  def current_period(as_of_date = Date.current)
    periods = recent_periods(as_of_date, count: 1, include_current: true)
    periods.first
  end

  # Get recent periods for display
  def recent_periods(as_of_date = Date.current, count: 5, include_current: true)
    periods = []
    current = calculate_period_containing(as_of_date)

    if include_current && current
      periods << current
    end

    # Walk backwards to find previous periods
    date = current ? current[:start] - 1.day : as_of_date
    (count - (include_current ? 1 : 0)).times do
      period = calculate_period_containing(date)
      break unless period

      periods << period
      date = period[:start] - 1.day
    end

    periods
  end

  # Calculate the period containing a given date
  def calculate_period_containing(date)
    anchor = period_anchor || organization.created_at.to_date

    case period_type
    when "weekly"
      calculate_weekly_period(date, anchor)
    when "biweekly"
      calculate_biweekly_period(date, anchor)
    when "semi_monthly"
      calculate_semi_monthly_period(date)
    when "monthly"
      calculate_monthly_period(date)
    end
  end

  # Calculate the payday for a period
  def payday_for_period(period)
    period_end = period[:end]

    case payday_timing
    when "period_end"
      period_end
    when "next_business_day"
      next_business_day(period_end)
    when "days_after"
      period_end + (payday_offset_days || 0).days
    else
      period_end
    end
  end

  private

  def set_defaults
    self.period_anchor ||= Date.current.beginning_of_week
    self.payday_offset_days ||= 0
    self.semi_monthly_days ||= "1_and_16" if semi_monthly?
  end

  def calculate_weekly_period(date, anchor)
    # Align to the anchor's day of week
    anchor_wday = anchor.wday
    date_wday = date.wday

    # Find the start of this week (aligned to anchor)
    days_since_anchor_weekday = (date_wday - anchor_wday) % 7
    period_start = date - days_since_anchor_weekday.days
    period_end = period_start + 6.days

    { start: period_start, end: period_end, payday: payday_for_period({ start: period_start, end: period_end }) }
  end

  def calculate_biweekly_period(date, anchor)
    # Calculate weeks since anchor
    days_since_anchor = (date - anchor).to_i
    weeks_since_anchor = days_since_anchor / 7

    # Which 2-week period are we in?
    period_number = weeks_since_anchor / 2
    period_start = anchor + (period_number * 14).days
    period_end = period_start + 13.days

    # If we're past this period's end, move to next
    if date > period_end
      period_start += 14.days
      period_end += 14.days
    end

    { start: period_start, end: period_end, payday: payday_for_period({ start: period_start, end: period_end }) }
  end

  def calculate_semi_monthly_period(date)
    case semi_monthly_days
    when "1_and_16"
      if date.day <= 15
        period_start = date.beginning_of_month
        period_end = Date.new(date.year, date.month, 15)
      else
        period_start = Date.new(date.year, date.month, 16)
        period_end = date.end_of_month
      end
    when "15_and_last"
      if date.day <= 14
        # First half: 1st to 14th
        period_start = date.beginning_of_month
        period_end = Date.new(date.year, date.month, 14)
      else
        # Second half: 15th to end of month
        period_start = Date.new(date.year, date.month, 15)
        period_end = date.end_of_month
      end
    else
      # Default fallback
      period_start = date.beginning_of_month
      period_end = Date.new(date.year, date.month, 15)
    end

    { start: period_start, end: period_end, payday: payday_for_period({ start: period_start, end: period_end }) }
  end

  def calculate_monthly_period(date)
    period_start = date.beginning_of_month
    period_end = date.end_of_month

    { start: period_start, end: period_end, payday: payday_for_period({ start: period_start, end: period_end }) }
  end

  def next_business_day(date)
    result = date
    # Move past weekends
    result += 1.day while result.saturday? || result.sunday?
    # TODO: Could add holiday checking here
    result
  end
end
