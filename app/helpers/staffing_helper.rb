# frozen_string_literal: true

module StaffingHelper
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
end
