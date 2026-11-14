# frozen_string_literal: true

# Reads an uploaded bill (a PDF) for superadmin Finances' Costs page: who
# it's from, its number, its total, the month it's for, and, on an Amazon
# invoice, what each service cost. What it finds fills a CompanyExpense
# that stays "to check" until someone confirms it against the PDF, so a
# misread never reaches Spent on its own.
#
# Knows four layouts: Amazon Web Services' monthly invoice, Anthropic's
# receipt (Stripe's standard receipt), GitHub's payment receipt (Copilot)
# and Mailgun's invoice (sending CocoScout's email). Anything else gets a
# best guess at the total and the date, and the rest is typed in.
class CompanyBillReader
  # "$1,284.37", "-$12.00", and Amazon's "USD 139.46" and "-USD 50.00".
  MONEY = /(-)?(?:USD\s?|\$\s?)(-)?([\d,]+\.\d{2})/
  DATE = /([A-Z][a-z]+)\.?\s+(\d{1,2})\s*,\s*(\d{4})/
  # GitHub writes its dates "2026-01-15" or "15 Jan 2026".
  ISO_DATE = /(\d{4})-(\d{2})-(\d{2})/
  DAY_FIRST_DATE = /(\d{1,2})\s+([A-Z][a-z]+)\.?,?\s+(\d{4})/
  # Mailgun writes its dates "11/13/2026", month first.
  US_DATE = %r{(\d{1,2})/(\d{1,2})/(\d{4})}
  # Lines in an Amazon invoice's Detail that are parts of a service, not one.
  NOT_A_SERVICE = /\A(charges|credits?|tax|vat|gst|ct|total|net charges|subtotal|discounts?|estimated|usage|summary|detail|aws service charges|savings plan \()/i

  Result = Data.define(:attributes, :found) do
    # Enough was read to count the bill once it's confirmed.
    def complete? = found.include?(:total) && found.include?(:month)
  end

  def self.read(io, filename: nil)
    text = begin
      PDF::Reader.new(io).pages.map(&:text).join("\n")
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, ArgumentError
      ""
    end
    from_text(text, filename: filename)
  end

  def self.from_text(text, filename: nil)
    new(text, filename: filename).result
  end

  def initialize(text, filename: nil)
    @text = text.to_s
    @flat = @text.gsub(/[ \t ]+/, " ")
    @filename = filename
  end

  def result
    attrs = if @flat.match?(/Amazon Web Services/i) then amazon
    elsif @flat.match?(/Anthropic/i) then anthropic
    elsif @flat.match?(/GitHub/i) then github
    elsif @flat.match?(/Mailgun/i) then mailgun
    else other
    end
    found = []
    found << :total if attrs[:bill_total_cents]
    found << :month if attrs[:period_month]
    found << :number if attrs[:bill_number]
    Result.new(attributes: attrs.compact, found: found)
  end

  private

  def amazon
    billed = date_after(/Invoice Date:?/i)
    credits = money_after(/^\s*Credits/)
    {
      vendor: "Amazon", category: "hosting", description: "Amazon Web Services",
      bill_number: @flat[/Invoice Number:?\s*([A-Z0-9-]+)/i, 1],
      bill_total_cents: money_after(/Total for this invoice/i) || money_after(/TOTAL AMOUNT DUE ON/i) || money_after(/AWS Service Charges/i),
      period_month: amazon_period || billed&.beginning_of_month,
      billed_on: billed,
      breakdown: amazon_services,
      # A bill Amazon's credits paid, in part or in full, says so: the
      # total is what was charged, not what the month would have cost.
      note: (ActiveSupport::NumberHelper.number_to_currency(credits.abs / 100.0).then { |amount| "Amazon credits covered #{amount} of this month." } if credits.to_i.nonzero?)
    }
  end

  # "This invoice is for the billing period January 1 - January 31 , 2026"
  def amazon_period
    match = @flat.match(/billing period\s+([A-Z][a-z]+)\.?\s+\d{1,2}(?:\s*,\s*(\d{4}))?\s*[-–]\s*[A-Z][a-z]+\.?\s+\d{1,2}\s*,\s*(\d{4})/i)
    return nil unless match

    month = month_number(match[1])
    month && Date.new((match[2] || match[3]).to_i, month, 1)
  end

  # Each service and what it cost, from the invoice's Detail section.
  def amazon_services
    lines = @flat.lines.map(&:strip)
    start = lines.index { |line| line.match?(/\ADetail\b/i) }
    return [] unless start

    lines[(start + 1)..].filter_map do |line|
      match = line.match(/\A(.+?)\s+#{MONEY.source}\z/)
      next unless match && !match[1].match?(NOT_A_SERVICE) && match[1].match?(/[A-Za-z]{3}/)

      amount = cents(match[2] || match[3], match[4])
      [ match[1].squish, amount ] if amount.nonzero?
    end
  end

  # Stripe's receipt: "Receipt number 2069-5479-2866", "Date paid October
  # 20, 2026", "Amount paid $181.18".
  def anthropic
    paid = date_after(/Date paid/i) || date_after(/paid on/i) || date_after(/Date of issue/i)
    {
      vendor: "Anthropic", category: "development", description: "Claude",
      bill_number: @flat[/Receipt number\s+([A-Z0-9-]+)/i, 1] || @flat[/Invoice number\s+([A-Z0-9-]+)/i, 1],
      bill_total_cents: money_after(/Amount paid/i) || @flat.match(/#{MONEY.source}\s+paid on/i)&.then { |m| cents(m[1] || m[2], m[3]) } ||
                        money_after(/Amount due/i) || money_after(/^\s*Total/i),
      period_month: paid&.beginning_of_month,
      billed_on: paid, paid_on: (paid if @flat.match?(/Date paid|paid on/i))
    }
  end

  # GitHub's payment receipt: "Total: $10.00 USD", "Transaction ID: ...",
  # "Date: 15 Jan 2026" (or 2026-01-15). The charge is for the month ahead,
  # so the day it was paid is the month it counts in.
  def github
    paid = date_after(/\bDate:?/) || first_date
    plan = @flat[/(Copilot[A-Za-z+ ]{0,24}?)(?=\s+(?:-|–|\(|\$|Month|Year|Qty|\d)|\s*$)/i, 1]&.squish
    {
      vendor: "GitHub", category: "development", description: plan ? "GitHub #{plan}" : "GitHub",
      bill_number: @flat[/(?:Transaction|Order|Receipt|Invoice) (?:ID|number|no\.?|#):?\s*([A-Za-z0-9_-]{4,})/i, 1],
      bill_total_cents: money_after(/\bTotal(?: paid| charged)?:?/) || money_after(/Amount(?: paid| charged)?:?/),
      period_month: paid&.beginning_of_month,
      billed_on: paid, paid_on: paid
    }
  end

  # Mailgun's invoice (Tim, 2026-11-14: Basic 10k since Nov 13, paid by Coco
  # Runs Everything): "Invoice Number: INV00010056", "Issue Date:
  # 11/13/2026", "Grand Total: $10.35 USD" (the plan plus Chicago's lease
  # tax), "Date of Payment: 11/13/2026". The plan's line and the tax are
  # its breakdown; a first month is prorated, and says so.
  def mailgun
    issued = us_date_after(/Issue Date:?/i)
    paid = us_date_after(/Date of Payment:?/i)
    plan = @flat[/Mailgun\s+(?:Basic|Foundation|Scale|Flex|Growth|Enterprise)(?:\s+\d+k)?/i]&.squish
    subtotal = money_after(/Sub ?total:/i)
    tax = money_after(/Subtotal Tax:/i)
    breakdown = [ ([ plan || "Mailgun plan", subtotal ] if subtotal), ([ "Tax", tax ] if tax.to_i.positive?) ].compact
    {
      vendor: "Mailgun", category: "software", description: plan || "Mailgun",
      bill_number: @flat[/Invoice Number:?\s*([A-Z0-9-]+)/i, 1],
      bill_total_cents: money_after(/Grand Total:/i) || money_after(/Invoice Total/i),
      period_month: (issued || paid)&.beginning_of_month,
      billed_on: issued, paid_on: paid,
      breakdown: breakdown,
      note: ("A first month, prorated." if @flat.match?(/Proration/i))
    }
  end

  # The first month-first date after a label on its line ("11/13/2026").
  def us_date_after(label)
    rest = @flat[Regexp.new("(?i:#{label.source})([^\\n]{0,40})"), 1]
    match = rest&.match(US_DATE)
    match && to_date(match[1].to_i, match[2], match[3])
  end

  def other
    day = date_after(/Date paid/i) || date_after(/Invoice date:?/i) || date_after(/Date:?/i) || first_date
    {
      vendor: File.basename(@filename.to_s, ".*").tr("_-", "  ").squish.presence&.truncate(60) || "Unknown",
      category: "other",
      bill_number: @flat[/(?:Invoice|Receipt) (?:number|no\.?|#):?\s*([A-Z0-9-]+)/i, 1],
      bill_total_cents: money_after(/Amount paid/i) || money_after(/Amount due/i) || money_after(/Total due/i) || money_after(/^\s*Total/i),
      period_month: day&.beginning_of_month,
      billed_on: day
    }
  end

  # The first amount after a label, on the same line or the next.
  def money_after(label)
    match = @flat.match(Regexp.new("(?i:#{label.source})[^\\n$]{0,80}?\\n?[^\\n$]{0,40}?#{MONEY.source}"))
    match && cents(match[-3] || match[-2], match[-1])
  end

  # The first date after a label on its line, however it's written.
  def date_after(label)
    rest = @flat[Regexp.new("(?i:#{label.source})([^\\n]{0,60})"), 1]
    rest && date_in(rest)
  end

  def first_date
    date_in(@flat)
  end

  # The earliest-placed date in a piece of text: "January 15, 2026",
  # "2026-01-15" or "15 Jan 2026".
  def date_in(text)
    found = [
      text.match(DATE)&.then { |m| [ m.begin(0), to_date(m[1], m[2], m[3]) ] },
      text.match(ISO_DATE)&.then { |m| [ m.begin(0), to_date(m[2].to_i, m[3], m[1]) ] },
      text.match(DAY_FIRST_DATE)&.then { |m| [ m.begin(0), to_date(m[2], m[1], m[3]) ] }
    ].compact.select(&:last)
    found.min_by(&:first)&.last
  end

  def to_date(month, day, year)
    number = month.is_a?(Integer) ? month : month_number(month)
    number && Date.valid_date?(year.to_i, number, day.to_i) ? Date.new(year.to_i, number, day.to_i) : nil
  end

  def month_number(name)
    index = Date::MONTHNAMES.index(name.to_s.capitalize) || Date::ABBR_MONTHNAMES.index(name.to_s.capitalize[0, 3])
    index&.positive? ? index : nil
  end

  def cents(sign, digits)
    value = (digits.delete(",").to_d * 100).round.to_i
    sign == "-" ? -value : value
  end
end
