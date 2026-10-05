# frozen_string_literal: true

# The public course page, in the storefront's words and numbers.
module CoursesHelper
  # What one registration costs, all in: the course and its tax, adding up to
  # the price shown (CourseTax's own math). One row means nothing to break down.
  def course_price_breakdown(offering, price_cents = offering.current_price_cents)
    quote = CourseTax.quote(offering, price_cents)
    rows = [ [ "Course", quote.base_cents ] ]
    rows << [ quote.label, quote.tax_cents ] if quote.tax_cents.positive?
    TicketingHelper::PriceBreakdown.new(rows: rows, total_cents: quote.total_cents)
  end

  # "incl. sales tax 8%", or nil when there's no tax on courses.
  def course_price_note(offering)
    quote = CourseTax.quote(offering)
    quote.tax_cents.positive? ? "incl. #{quote.label.downcase}" : nil
  end

  # The lines a registration was paid in: the course, then its tax (muted).
  def course_registration_lines(registration)
    lines = [ [ "Course fee", registration.amount_cents, false ] ]
    lines << [ CourseTax.quote(registration.course_offering).label, registration.tax_cents, true ] if registration.tax_cents.to_i.positive?
    lines
  end

  # "7:00 – 9:00 PM" / "11:30 AM – 1:00 PM" / "7:00 PM".
  def course_session_time(show)
    starts = show.date_and_time
    return starts.strftime("%-l:%M %p") unless show.duration_minutes.present?

    ends = starts + show.duration_minutes.minutes
    if starts.strftime("%p") == ends.strftime("%p")
      "#{starts.strftime('%-l:%M')} – #{ends.strftime('%-l:%M %p')}"
    else
      "#{starts.strftime('%-l:%M %p')} – #{ends.strftime('%-l:%M %p')}"
    end
  end
end
