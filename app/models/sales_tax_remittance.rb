# frozen_string_literal: true

# One period of one tax the organization has paid the government, marked on
# the Sales tax page. Its tax stops being set aside (SalesTaxSetAside), and
# the books move the amount out of "Tax to pay the government" and the bank.
# Undoing it (a mistake) puts both back.
class SalesTaxRemittance < ApplicationRecord
  BASES = TicketTaxReport::BASES

  belongs_to :organization
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :tax_name, :period_start, :period_end, :paid_on, presence: true
  validates :basis, inclusion: { in: BASES }
  validates :rate_bps, :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :period_in_order

  after_save :post_to_books
  before_destroy :unpost_from_books

  def covers?(from, to, basis:)
    self.basis == basis && period_start <= from && period_end >= to
  end

  def exact?(from, to, basis:)
    self.basis == basis && period_start == from && period_end == to
  end

  private

  def period_in_order
    errors.add(:period_end, "comes before the start") if period_start && period_end && period_end < period_start
  end

  def post_to_books
    LedgerPosting.post!(organization: organization, source: self, kind: "tax_paid", entry_date: paid_on, cash_date: paid_on,
                        memo: "#{tax_name} paid to the government",
                        lines: [
                          { account: :tax_to_remit, amount_cents: amount_cents },
                          { account: :bank, amount_cents: -amount_cents }
                        ])
  end

  def unpost_from_books
    LedgerPosting.post!(organization: organization, source: self, kind: "tax_paid", entry_date: paid_on, cash_date: paid_on, lines: [])
  end
end
