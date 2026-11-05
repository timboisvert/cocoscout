# frozen_string_literal: true

# One bill for running CocoScout that never passes through Stripe: an Amazon
# invoice, a Claude receipt, a developer program. Coco Runs Everything pays
# it (or reimburses Tim for it), so CocoScout's own ledger, which has to
# match Stripe to the cent, never sees it. CocoScoutFinances and
# CocoScoutMoneyNow add these on top, so Spent and Profit are whole.
#
#   bill_total_cents  what the bill says
#   share_percent     how much of it is CocoScout's (a reimbursed Claude
#                     receipt is 50%)
#   amount_cents      the cost to CocoScout: the total times the share
#   period_month      the month it's for (the 1st), which is the month it
#                     counts in; paid_on is the day the money left
#   confirmed_at      nil while it's only been read off an uploaded PDF;
#                     a bill counts once someone has checked it
#
# CocoScout only: the company's other business is not recorded here.
class CompanyExpense < ApplicationRecord
  CATEGORIES = {
    "hosting" => "Hosting",
    "software" => "Software and subscriptions",
    "programs" => "Developer programs and licenses",
    "professional" => "Legal and professional",
    "marketing" => "Marketing",
    "other" => "Other"
  }.freeze

  PAID_BY = {
    "company" => "Coco Runs Everything paid it",
    "reimbursed" => "Tim paid it and the company reimbursed it"
  }.freeze

  has_many_attached :documents

  before_validation :normalize

  validates :vendor, presence: true
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :paid_by, inclusion: { in: PAID_BY.keys }
  validates :bill_total_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :share_percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :bill_number, uniqueness: { scope: :vendor, allow_nil: true, message: "is already here for this vendor" }
  # A bill that counts needs its amount and its month.
  validates :period_month, presence: { message: "is needed: which month is it for?" }, if: :confirmed?
  validates :bill_total_cents, numericality: { greater_than: 0, message: "is needed" }, if: :confirmed?

  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :to_check, -> { where(confirmed_at: nil) }
  scope :for_year, ->(year) { where(period_month: Date.new(year.to_i, 1, 1)..Date.new(year.to_i, 12, 31)) }
  # Newest month first, and within a month the latest paid first (the day
  # it was billed when there's no paid day).
  scope :newest_first, -> { order(Arel.sql("period_month DESC NULLS FIRST, COALESCE(paid_on, billed_on) DESC NULLS LAST, id DESC")) }
  scope :oldest_first, -> { order(Arel.sql("period_month ASC, COALESCE(paid_on, billed_on) ASC NULLS LAST, id ASC")) }

  # Confirmed bills for the months a time range touches (nil: all of them).
  def self.counted_in(range)
    return confirmed unless range

    confirmed.where(period_month: range.first.to_date.beginning_of_month..range.last.to_date)
  end

  def self.category_label(key)
    CATEGORIES.fetch(key.to_s, key.to_s.humanize)
  end

  def self.years
    ((confirmed.pluck(Arel.sql("DISTINCT EXTRACT(YEAR FROM period_month)::int")).compact + [ Date.current.year ]).uniq).sort.reverse
  end

  def confirmed? = confirmed_at.present?
  def category_label = self.class.category_label(category)
  def paid_by_label = PAID_BY.fetch(paid_by, paid_by.to_s.humanize)
  def partial_share? = share_percent.to_d < 100

  # The part of the bill that isn't CocoScout's.
  def not_ours_cents = bill_total_cents.to_i - amount_cents.to_i

  private

  def normalize
    self.vendor = vendor.to_s.squish.presence
    self.bill_number = bill_number.to_s.squish.presence
    self.description = description.to_s.squish.presence
    self.period_month = period_month&.beginning_of_month
    self.share_percent = 100 if share_percent.blank?
    self.amount_cents = (bill_total_cents.to_i * share_percent.to_d / 100).round
    self.breakdown = [] unless breakdown.is_a?(Array)
  end
end
