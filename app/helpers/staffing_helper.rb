# frozen_string_literal: true

module StaffingHelper
  # Standard ACH funding clears, then Connect payouts settle to each person's
  # bank. This window is what a manager actually cares about ("if I pay today,
  # when do they get the money?"). An estimate — weekends are skipped, holidays
  # aren't modeled.
  DEPOSIT_ESTIMATE_BUSINESS_DAYS = 2..4

  # Add N business days to a date, skipping weekends. Holidays aren't modeled —
  # these power the estimated pay-timing display, which is explicitly an estimate.
  def add_business_days(date, count)
    date = date.to_date
    count.times do
      loop do
        date += 1
        break unless date.saturday? || date.sunday?
      end
    end
    date
  end

  # [earliest, latest] estimated deposit dates if a run is funded on `from`.
  def estimated_deposit_window(from = Date.current)
    [ add_business_days(from, DEPOSIT_ESTIMATE_BUSINESS_DAYS.first),
      add_business_days(from, DEPOSIT_ESTIMATE_BUSINESS_DAYS.last) ]
  end
end
