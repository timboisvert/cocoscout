# frozen_string_literal: true

# One answer to "when does this series stop?" for every place a series is
# built or grown — the show wizard, the production wizard, and the series
# modal's rebuild and extend. It's a date the manager picks, like a contract's
# "Until". The retired preset menu (3/6/12 months, end of year, custom) is
# still understood, so anything that still posts it lands on the same date.
module RecurrenceEndDate
  # What the date field starts at when nothing's been chosen yet.
  DEFAULT_SPAN = 3.months

  # Date, or nil when nothing usable was given (callers pick their own default).
  def self.resolve(start_date, end_date: nil, end_type: nil, custom: nil)
    explicit = parse(end_date)
    return explicit if explicit

    start_date = start_date.to_date
    case end_type.to_s
    when "3_months"   then start_date + 3.months
    when "6_months"   then start_date + 6.months
    when "12_months"  then start_date + 12.months
    when "end_of_year"
      eoy = Date.new(start_date.year, 12, 31)
      eoy <= start_date ? Date.new(start_date.year + 1, 12, 31) : eoy
    when "custom"     then parse(custom)
    end
  end

  def self.default_for(start_date)
    start_date.to_date + DEFAULT_SPAN
  end

  def self.parse(value)
    return nil if value.blank?
    Date.parse(value.to_s)
  rescue Date::Error, TypeError
    nil
  end
end
