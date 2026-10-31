# frozen_string_literal: true

# Reads the transactions out of a bank statement file (Books V1.3, plan D3):
# a CSV in any of the common bank layouts, or an OFX/QFX download. Given
# the file's text, never the file; nothing here writes to disk.
#
#   result = BankStatementParser.parse(text, filename: "october.csv")
#   result.lines  # => [{ on:, amount_cents:, description:, fitid: }]
#
# CSV: the header names the columns; a date column, a description column
# (description, memo, payee, name, details) and either one amount column
# or a debit and a credit column. Withdrawals come out negative.
class BankStatementParser
  class Unreadable < StandardError; end

  Result = Struct.new(:format, :lines, :closing_balance_cents, :closing_on, keyword_init: true)

  DATE_HEADERS = %w[date posted posteddate postingdate transactiondate trandate effectivedate].freeze
  DESCRIPTION_HEADERS = %w[description memo payee name details narrative transaction transactiondescription].freeze
  AMOUNT_HEADERS = %w[amount transactionamount amt].freeze
  DEBIT_HEADERS = %w[debit withdrawal withdrawals debitamount moneyout paidout].freeze
  CREDIT_HEADERS = %w[credit deposit deposits creditamount moneyin paidin].freeze

  def self.parse(text, filename: nil)
    text = text.to_s.dup.force_encoding("UTF-8").scrub
    text = text.delete_prefix("﻿")
    if text.match?(/<OFX>|<STMTTRN>|OFXHEADER/i) || filename.to_s.match?(/\.(ofx|qfx)\z/i)
      parse_ofx(text)
    else
      parse_csv(text)
    end
  end

  def self.parse_ofx(text)
    lines = text.scan(%r{<STMTTRN>(.*?)(?:</STMTTRN>|(?=<STMTTRN>)|\z)}mi).map(&:first).filter_map do |block|
      on = ofx_date(ofx_tag(block, "DTPOSTED"))
      amount = ofx_tag(block, "TRNAMT")
      next if on.nil? || amount.blank?

      { on: on, amount_cents: cents(amount), description: [ ofx_tag(block, "NAME"), ofx_tag(block, "MEMO") ].compact_blank.uniq.join(" · "), fitid: ofx_tag(block, "FITID") }
    end
    raise Unreadable, "No transactions in this OFX file." if lines.empty?

    ledger = text[%r{<LEDGERBAL>(.*?)(?:</LEDGERBAL>|\z)}mi, 1]
    Result.new(format: "ofx", lines: lines.reject { |l| l[:amount_cents].zero? },
               closing_balance_cents: (ledger && ofx_tag(ledger, "BALAMT").presence && cents(ofx_tag(ledger, "BALAMT"))),
               closing_on: (ledger && ofx_date(ofx_tag(ledger, "DTASOF"))))
  end

  def self.parse_csv(text)
    rows = CSV.parse(text, liberal_parsing: true).reject { |r| r.compact_blank.empty? }
    raise Unreadable, "The file is empty." if rows.empty?

    header_index = rows.index { |r| columns_for(r).key?(:date) && (columns_for(r).key?(:amount) || columns_for(r).key?(:debit)) }
    raise Unreadable, "Couldn't find the columns. The first row should name them: a date, a description, and an amount (or debit and credit)." if header_index.nil?

    cols = columns_for(rows[header_index])
    lines = rows.drop(header_index + 1).filter_map do |row|
      on = parse_date(row[cols[:date]])
      next if on.nil?

      amount = if cols[:amount]
        cents(row[cols[:amount]])
      else
        credit = cents(row[cols[:credit]].presence || "0")
        debit = cents(row[cols[:debit]].presence || "0")
        credit - debit.abs
      end
      next if amount.zero?

      { on: on, amount_cents: amount, description: (cols[:description] ? row[cols[:description]].to_s.strip.squeeze(" ") : ""), fitid: nil }
    end
    raise Unreadable, "No transactions in this file." if lines.empty?

    Result.new(format: "csv", lines: lines, closing_balance_cents: nil, closing_on: nil)
  end

  def self.columns_for(row)
    found = {}
    row.each_with_index do |raw, i|
      key = raw.to_s.downcase.gsub(/[^a-z]/, "")
      next if key.blank?

      found[:date] ||= i if DATE_HEADERS.include?(key) || key.end_with?("date")
      found[:description] ||= i if DESCRIPTION_HEADERS.include?(key)
      found[:amount] ||= i if AMOUNT_HEADERS.include?(key)
      found[:debit] ||= i if DEBIT_HEADERS.include?(key)
      found[:credit] ||= i if CREDIT_HEADERS.include?(key)
    end
    found.delete(:amount) if found[:debit] && found[:credit] && found[:amount] && found[:amount] > [ found[:debit], found[:credit] ].max
    found
  end

  def self.cents(value)
    s = value.to_s.strip
    negative = s.start_with?("(") || s.include?("-") || s.end_with?("DR")
    digits = s.gsub(/[^0-9.]/, "")
    return 0 if digits.blank?

    amount = (digits.to_d * 100).round
    negative ? -amount : amount
  end

  def self.parse_date(value)
    s = value.to_s.strip
    return nil if s.blank?

    [ "%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d", "%d-%b-%Y", "%b %d, %Y", "%d/%m/%Y", "%Y/%m/%d", "%m-%d-%Y" ].each do |fmt|
      return Date.strptime(s, fmt)
    rescue ArgumentError
      next
    end
    Date.parse(s)
  rescue ArgumentError
    nil
  end

  def self.ofx_tag(block, name)
    block[%r{<#{name}>([^<\r\n]*)}i, 1]&.strip
  end

  def self.ofx_date(value)
    return nil if value.blank?

    Date.strptime(value[0, 8], "%Y%m%d")
  rescue ArgumentError
    nil
  end
end
