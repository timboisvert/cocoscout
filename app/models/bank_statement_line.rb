# frozen_string_literal: true

# One line of a bank statement, newest first on the page: the date, the amount (deposits positive,
# withdrawals negative) and the bank's description. Nothing else from the
# file is kept. Each line ends up matched to a line already on the books
# (or to a group of them: one deposit from a ticket seller, several shows'
# entries), recorded as new money, or ignored (a transfer between the
# organization's own accounts, a personal charge).
#
# description_key is the description with the bank's noise taken out (ids,
# dates, amounts), so a line can find what was done with the same payee
# last time.
class BankStatementLine < ApplicationRecord
  STATES = %w[open suggested matched recorded ignored].freeze
  # The parts of a bank description that change every time.
  NOISE = /\b(ORIG|IND|TRACE|EED|TRN|CO|SEC|ID|NAME|ENTRY|DESCR|CCD|PPD|WEB|TEL|POS|DEBIT|CREDIT|CARD|PURCHASE|PAYMENT|ONLINE|ACH|TRANSFER|WITHDRAWAL|DEPOSIT)\b|[#*]\s*\w+|\b\w*\d\w*\b/i

  belongs_to :bank_statement_import
  belongs_to :organization
  belongs_to :journal_line, optional: true
  belongs_to :money_record, optional: true

  validates :on, :fingerprint, presence: true
  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :state, inclusion: { in: STATES }

  before_validation do
    self.fingerprint ||= self.class.fingerprint_for(on, amount_cents, description)
    self.description_key ||= self.class.description_key_for(description)
  end

  scope :to_deal_with, -> { where(state: %w[open suggested]).order(on: :desc, id: :desc) }
  scope :done, -> { where(state: %w[matched recorded ignored]) }

  # seq: the nth identical line on the same day (0 for the first; its
  # fingerprint is the same as before seq existed).
  def self.fingerprint_for(on, amount_cents, description, seq = 0)
    text = "#{on}|#{amount_cents}|#{description.to_s.strip.downcase.squeeze(' ')}"
    text += "|#{seq}" if seq.to_i.positive?
    Digest::SHA256.hexdigest(text)[0, 40]
  end

  def self.description_key_for(description)
    key = description.to_s.upcase.gsub(NOISE, " ").gsub(/[^A-Z&' ]/, " ").squeeze(" ").strip
    key.presence&.first(40)
  end

  def deposit? = amount_cents.positive?
  def open? = state == "open"
  def suggested? = state == "suggested"
  def done? = state.in?(%w[matched recorded ignored])

  # The lines on the books this one matches or looks like: one, or a group.
  def all_journal_line_ids = journal_line_ids.presence || [ journal_line_id ].compact
  def group? = journal_line_ids.size > 1
  def journal_lines = JournalLine.where(id: all_journal_line_ids)

  # lines: one JournalLine or several (a group that adds up to this line).
  def match!(lines)
    lines = Array(lines)
    update!(state: "matched", journal_line: lines.first, journal_line_ids: lines.map(&:id), money_record: nil)
  end

  def suggest!(lines)
    lines = Array(lines)
    update!(state: "suggested", journal_line: lines.first, journal_line_ids: lines.map(&:id), money_record: nil)
  end

  def ignore!
    update!(state: "ignored", journal_line: nil, journal_line_ids: [], money_record: nil)
  end

  def reopen!
    update!(state: "open", journal_line: nil, journal_line_ids: [], money_record: nil)
  end

  # Money recorded by hand from this line: the record's own bank line is the match.
  def recorded!(record)
    bank = record.journal_entries.find { |e| e.reversed_at.nil? && e.reversal_of_id.nil? }&.journal_lines&.find { |l| l.ledger_account.key == "bank" }
    update!(state: "recorded", money_record: record, journal_line: bank, journal_line_ids: [ bank&.id ].compact)
  end
end
