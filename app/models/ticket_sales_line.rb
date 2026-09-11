# frozen_string_literal: true

# What one ticket source sold for one show: how many, and for how much.
#
# The lines are the truth. show_financials.ticket_count and .ticket_revenue are
# kept as rollups of them (see ShowFinancials#recalculate_ticket_totals!) so the
# thirty-odd places that read those two columns — every contract settlement, the
# per-ticket payout methods, the reports — carry on unchanged.
class TicketSalesLine < ApplicationRecord
  belongs_to :show_financials
  belongs_to :ticket_source, optional: true

  validates :tickets_sold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position, :id) }

  # One write path for the rollup, so the cached columns can never drift from
  # the lines that feed them.
  after_save :refresh_totals
  after_destroy :refresh_totals

  # What this line is called on screen. A line entered before the org named any
  # sources — or one whose source was archived away — still has an amount worth
  # showing, so it gets a neutral label rather than a blank.
  def source_name
    ticket_source&.name.presence || "Ticket sales"
  end

  def blank_entry?
    tickets_sold.to_i.zero? && amount.to_f.zero?
  end

  private

  def refresh_totals
    show_financials&.recalculate_ticket_totals!
  end
end
