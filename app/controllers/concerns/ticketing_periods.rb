# frozen_string_literal: true

# The periods a ticketing report can cover: the last 12 months and the last
# 4 quarters, newest first. Shared by the taxes and sales reports so their
# selectors match.
module TicketingPeriods
  extend ActiveSupport::Concern

  private

  def period_choices
    today = Date.current
    months = (0..11).map do |i|
      start = today.beginning_of_month << i
      { key: start.strftime("%Y-%m"), label: start.strftime("%B %Y"), from: start, to: start.end_of_month }
    end
    quarters = (0..3).map do |i|
      start = (today.beginning_of_quarter << (3 * i))
      { key: "#{start.year}-Q#{((start.month - 1) / 3) + 1}", label: "Q#{((start.month - 1) / 3) + 1} #{start.year}",
        from: start, to: start.end_of_quarter }
    end
    months + quarters
  end

  def chosen_period
    @periods = period_choices
    @period = @periods.find { |p| p[:key] == params[:period] } || @periods.first
  end
end
