# frozen_string_literal: true

# Tax on a course registration, from the theater's one course-tax setting
# (TicketTaxSetting, money kind "courses"):
#
#   quote    — what a registration at the offering's current price carries:
#              the price before tax, the tax, and whether it's added at
#              checkout or was inside the price all along
#   record!  — the permanent tax lines for a paid registration, like a
#              ticket's, so the taxes-collected report sees it
#   reverse! — the lines undone on a refund
#
# A registration's amount_cents is always the price before tax; fees, the
# instructor split and the payout calc never see the tax.
class CourseTax
  Quote = Data.define(:base_cents, :tax_cents, :mode, :result) do
    # What the student is charged.
    def total_cents
      mode == "added" ? base_cents + tax_cents : base_cents + tax_cents
    end

    def added?
      mode == "added" && tax_cents.positive?
    end

    def label
      line = result.lines.reject(&:exempt).first
      line ? "#{line.name} #{format('%g', line.rate_bps / 100.0)}%" : "Tax"
    end
  end

  # price_cents: the offering's current price, which includes the tax when
  # the theater said the tax is inside its prices.
  def self.quote(offering, price_cents = offering.current_price_cents)
    result = TaxCalculator.for_course(offering, price_cents)
    if result.mode == "included"
      tax = result.tax_cents
      Quote.new(base_cents: price_cents - tax, tax_cents: tax, mode: "included", result: result)
    else
      Quote.new(base_cents: price_cents, tax_cents: result.added_cents, mode: "added", result: result)
    end
  end

  # The lines for a registration that was just paid. Rates can change while
  # a student is checking out, so the amount recorded is what was charged
  # (registration.tax_cents), under the rate in force now.
  def self.record!(registration)
    return if registration.tax_cents.to_i.zero? || registration.tax_lines.exists?

    offering = registration.course_offering
    result = TaxCalculator.for_course(offering, registration.amount_cents)
    line = result.lines.reject(&:exempt).first
    TaxLine.create!(organization_id: offering.production.organization_id, taxable: registration,
                    tax_rate: line&.tax_rate, name: line&.name || "Sales tax", rate_bps: line&.rate_bps || 0,
                    jurisdiction: line&.jurisdiction, remitter: "organization", included: result.mode == "included",
                    exempt: false, base_cents: registration.amount_cents, tax_cents: registration.tax_cents,
                    sale_date: (registration.paid_at || Time.current).to_date, event_date: offering.try(:start_date))
  end

  def self.reverse!(registration)
    TaxLine.where(taxable: registration, reversal_of_id: nil).where("tax_cents >= 0").find_each do |line|
      next if TaxLine.exists?(reversal_of_id: line.id)

      TaxLine.create!(line.attributes.except("id", "created_at", "updated_at")
                          .merge("base_cents" => -line.base_cents, "tax_cents" => -line.tax_cents,
                                 "sale_date" => Date.current, "reversal_of_id" => line.id))
    end
  end

  # "+ 10.25% sales tax" under a course's price, or nil when there's none.
  def self.price_note(offering)
    q = quote(offering)
    return nil unless q.tax_cents.positive?

    q.mode == "added" ? "+ #{q.label.downcase}" : "incl. #{q.label.downcase}"
  end
end
