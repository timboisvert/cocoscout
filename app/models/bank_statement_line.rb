# frozen_string_literal: true

# One line of a bank statement: the date, the amount (deposits positive,
# withdrawals negative) and the bank's description. Nothing else from the
# file is kept. Each line ends up matched to a line already on the books,
# recorded as new money, or ignored (a transfer between the organization's
# own accounts, a personal charge).
class BankStatementLine < ApplicationRecord
  STATES = %w[open suggested matched recorded ignored].freeze

  belongs_to :bank_statement_import
  belongs_to :organization
  belongs_to :journal_line, optional: true
  belongs_to :money_record, optional: true

  validates :on, :fingerprint, presence: true
  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :state, inclusion: { in: STATES }

  before_validation { self.fingerprint ||= self.class.fingerprint_for(on, amount_cents, description) }

  scope :to_deal_with, -> { where(state: %w[open suggested]).order(:on, :id) }
  scope :done, -> { where(state: %w[matched recorded ignored]) }

  def self.fingerprint_for(on, amount_cents, description)
    Digest::SHA256.hexdigest("#{on}|#{amount_cents}|#{description.to_s.strip.downcase.squeeze(' ')}")[0, 40]
  end

  def deposit? = amount_cents.positive?
  def open? = state == "open"
  def suggested? = state == "suggested"
  def done? = state.in?(%w[matched recorded ignored])

  def match!(line)
    update!(state: "matched", journal_line: line, money_record: nil)
  end

  def ignore!
    update!(state: "ignored", journal_line: nil, money_record: nil)
  end

  def reopen!
    update!(state: "open", journal_line: nil, money_record: nil)
  end

  # Money recorded by hand from this line: the record's own bank line is the match.
  def recorded!(record)
    bank = record.journal_entries.find { |e| e.reversed_at.nil? && e.reversal_of_id.nil? }&.journal_lines&.find { |l| l.ledger_account.key == "bank" }
    update!(state: "recorded", money_record: record, journal_line: bank)
  end
end
