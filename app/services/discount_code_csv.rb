# frozen_string_literal: true

require "csv"

# Discount codes as a spreadsheet (Tim, 2026-11-07): the codes a production
# or a date lists, exported as a CSV, and a CSV's codes added in bulk, onto
# another production or date or after editing them in a spreadsheet. The
# columns are the ones a manager types when adding one code (code, kind,
# amount, most uses, who it's shared with); uses aren't carried, they're
# counted from orders.
class DiscountCodeCsv
  HEADERS = [ "Code", "Kind", "Amount", "Most uses", "Shared with" ].freeze

  Result = Data.define(:added, :skipped, :errors) do
    def ok?
      errors.empty? && added.any?
    end

    # "Added 3 codes. 1 already here, skipped: FRIENDS."
    def summary
      parts = []
      parts << "Added #{added.one? ? added.first.code : "#{added.size} codes"}." if added.any?
      parts << "#{skipped.size == 1 ? 'Already here, skipped' : "#{skipped.size} already here, skipped"}: #{skipped.join(', ')}." if skipped.any?
      parts << errors.join(" ") if errors.any?
      parts << "No codes added." if parts.empty?
      parts.join(" ")
    end
  end

  def self.export(codes)
    CSV.generate do |csv|
      csv << HEADERS
      codes.each do |code|
        csv << [ code.code, code.kind == "percent" ? "% off" : "$ off", amount_words(code), code.max_uses, TicketDiscountCode::SHARED_WITH_LABELS[code.shared_with] ]
      end
    end
  end

  def self.amount_words(code)
    code.kind == "percent" ? format("%g", code.percent) : format("%.2f", code.amount_cents.to_i / 100.0)
  end

  # file: an uploaded CSV; text: pasted lines (either). scope: production: or
  # ticket_listing:. A code already active in that scope is skipped, not
  # doubled; a row that can't be read is reported with its line number.
  def self.import(organization:, file: nil, text: nil, **scope)
    body = file.respond_to?(:read) ? file.read.to_s : text.to_s
    rows = parse(body)
    return Result.new(added: [], skipped: [], errors: [ "That isn't a spreadsheet we can read: save it as CSV with a Code column." ]) if rows.nil?

    existing = organization.ticket_discount_codes.where(active: true, **scope).pluck(:code).to_set
    added = []
    skipped = []
    errors = []
    rows.each_with_index do |row, i|
      next if row.values.all?(&:blank?)

      raw = { code: row["code"], kind: kind_from(row["kind"], row["amount"]), amount: row["amount"],
              max_uses: row["most uses"].presence, shared_with: shared_with_from(row["shared with"]) }
      code = organization.ticket_discount_codes.new(TicketDiscountCode.attributes_from_form(raw).merge(scope))
      if existing.include?(code.code)
        skipped << code.code
      elsif code.save
        added << code
        existing << code.code
      else
        errors << "Line #{i + 2}#{" (#{code.code})" if code.code.present?}: #{code.errors.full_messages.to_sentence.downcase_first}."
      end
    end
    Result.new(added: added, skipped: skipped, errors: errors)
  end

  # Rows keyed by lowercase header; nil when it isn't CSV with a Code column.
  def self.parse(body)
    body = body.dup.force_encoding("UTF-8").delete_prefix("﻿")
    table = CSV.parse(body, headers: true, skip_blanks: true, header_converters: ->(h) { h.to_s.strip.downcase })
    return nil unless table.headers.include?("code")

    table.map(&:to_h)
  rescue CSV::MalformedCSVError, ArgumentError
    nil
  end

  def self.kind_from(kind, amount)
    return "percent" if kind.to_s.match?(/%|percent/i)
    return "percent" if kind.blank? && amount.to_s.strip.end_with?("%")

    "fixed"
  end

  # A label ("Production team only"), a key ("team"), or blank for the default.
  def self.shared_with_from(words)
    text = words.to_s.strip.downcase
    return "team_and_cast" if text.blank?

    TicketDiscountCode::SHARED_WITH_LABELS.find { |key, label| text == key || text == label.downcase }&.first || "team_and_cast"
  end
  private_class_method :parse, :kind_from, :shared_with_from, :amount_words
end
