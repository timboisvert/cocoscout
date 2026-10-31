# frozen_string_literal: true

# One payment on an invoice: collected online on the pay page (via
# "online", and then the CocoScout balance holds it, posted from its cash
# entry), or recorded by hand when a check or transfer came (posted here:
# income arriving in the bank).
class InvoicePayment < ApplicationRecord
  VIA = { "online" => "Online", "check" => "Check", "cash" => "Cash", "bank_transfer" => "Bank transfer", "zelle" => "Zelle", "venmo" => "Venmo" }.freeze

  belongs_to :invoice
  belongs_to :organization
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :on, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :via, inclusion: { in: VIA.keys }

  after_commit :post_to_books, on: %i[create update]
  after_commit :unpost_from_books, on: :destroy

  def online? = via == "online"
  def via_label = VIA.fetch(via)

  # Hand-recorded money lands in the bank (cash in the door box). Online
  # money is the balance's: its OrgCashEntry posts it.
  def post_to_books
    return if online?

    dims = { production: invoice.production, show: invoice.show }
    account = via == "cash" ? :door_cash : :bank
    LedgerPosting.post!(organization: organization, source: self, kind: "invoice_payment", entry_date: on, cash_date: on,
                        memo: "Invoice #{invoice.display_number} paid by #{via_label.downcase}#{reference.present? ? " (#{reference})" : ''}",
                        lines: [ { account: account, amount_cents: amount_cents }.merge(dims),
                                 { account: invoice.category_account, amount_cents: -amount_cents, memo: invoice.bill_to_name }.merge(dims) ])
  end

  def unpost_from_books
    LedgerPosting.unpost!(source: self, kind: "invoice_payment")
  end
end
