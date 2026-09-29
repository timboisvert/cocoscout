# frozen_string_literal: true

module Tax
  # Dates that matter for 1099-NECs.
  module Calendar
    module_function

    # The tax year a manager is working toward right now: January and February
    # are spent on last year's forms, the rest of the year collects for this one.
    def working_tax_year(today = Date.current)
      today.month <= 2 ? today.year - 1 : today.year
    end

    # 1099-NECs are due to recipients AND the IRS by January 31 of the next
    # year, pushed to the next business day when that falls on a weekend.
    def nec_due_date(tax_year)
      date = Date.new(tax_year + 1, 1, 31)
      date += 1 while date.saturday? || date.sunday?
      date
    end
  end
end
