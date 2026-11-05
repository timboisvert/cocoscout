# frozen_string_literal: true

# Reads an uploaded bill (a PDF) for superadmin Finances' Costs page: who
# it's from, its number, its total, the month it's for, and, on an Amazon
# invoice, what each service cost. What it finds fills a CompanyExpense
# that stays "to check" until someone confirms it against the PDF, so a
# misread never reaches Spent on its own.
#
# Knows two layouts well: Amazon Web Services' monthly invoice and
# Anthropic's receipt (Stripe's standard receipt). Anything else gets a
# best guess at the total and the date, and the rest is typed in.
class CompanyBillReader
  MONEY = /(?:USD\s*)?(-?)\$\s?([\d,]+\.\d{2})/
  DATE = /([A-Z][a-z]+)\.?\s+(\d{1,2})\s*,\s*(\d{4})/
  # Lines in an Amazon invoice's Detail that are parts of a service, not one.
  NOT_A_SERVICE = /\A(charges|credits?|tax|vat|gst|ct|total|net charges|subtotal|discounts?|estimated|usage|summary|detail|aws service charges)\b/i

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
    else other
    end
    found = []
    found << :total if attrs[:bill_total_cents].to_i.positive?
    found << :month if attrs[:period_month]
    found << :number if attrs[:bill_number]
    Result.new(attributes: attrs.compact, found: found)
  end

  private

  def amazon
    billed = date_after(/Invoice Date:?/i)
    {
      vendor: "Amazon", category: "hosting", description: "Amazon Web Services",
      bill_number: @flat[/Invoice Number:?\s*([A-Z0-9-]+)/i, 1],
      bill_total_cents: money_after(/Total for this invoice/i) || money_after(/TOTAL AMOUNT DUE[^$\n]*/i) || money_after(/AWS Service Charges/i),
      period_month: amazon_period || billed&.beginning_of_month,
      billed_on: billed,
      breakdown: amazon_services
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

      [ match[1].squish, cents(match[2], match[3]) ]
    end
  end

  # Stripe's receipt: "Receipt number 2069-5479-2866", "Date paid October
  # 20, 2026", "Amount paid $181.18".
  def anthropic
    paid = date_after(/Date paid/i) || date_after(/paid on/i) || date_after(/Date of issue/i)
    {
      vendor: "Anthropic", category: "software", description: "Claude",
      bill_number: @flat[/Receipt number\s+([A-Z0-9-]+)/i, 1] || @flat[/Invoice number\s+([A-Z0-9-]+)/i, 1],
      bill_total_cents: money_after(/Amount paid/i) || @flat.match(/#{MONEY.source}\s+paid on/i)&.then { |m| cents(m[1], m[2]) } ||
                        money_after(/Amount due/i) || money_after(/^\s*Total/i),
      period_month: paid&.beginning_of_month,
      billed_on: paid, paid_on: (paid if @flat.match?(/Date paid|paid on/i))
    }
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
    match = @flat.match(Regexp.new("(?i:#{label.source})[^\\n$]{0,80}\\n?[^\\n$]{0,40}#{MONEY.source}"))
    match && cents(match[-2], match[-1])
  end

  def date_after(label)
    match = @flat.match(Regexp.new("(?i:#{label.source})[^\\n]{0,20}?#{DATE.source}"))
    match && to_date(match[-3], match[-2], match[-1])
  end

  def first_date
    match = @flat.match(DATE)
    match && to_date(match[1], match[2], match[3])
  end

  def to_date(month, day, year)
    number = month_number(month)
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
