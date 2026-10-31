# frozen_string_literal: true

# One payment on a bill, part or whole: that much of the bill's category,
# paid from the account it came from, counted when it moved.
class BillPayment < ApplicationRecord
  belongs_to :bill
  belongs_to :organization
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :on, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :via, inclusion: { in: Bill::VIA.keys }

  after_commit :post_to_books, on: %i[create update]
  after_commit :unpost_from_books, on: :destroy

  def via_label = Bill::VIA.dig(via, 0)
  def via_account = Bill::VIA.dig(via, 1)

  def post_to_books
    dims = { production: bill.production, show: bill.show }
    LedgerPosting.post!(organization: organization, source: self, kind: "bill_payment", entry_date: on, cash_date: on,
                        memo: "#{bill.vendor_name} paid#{reference.present? ? " (#{reference})" : ''}",
                        lines: [ { account: bill.category_account, amount_cents: amount_cents, memo: bill.vendor_name }.merge(dims),
                                 { account: via_account, amount_cents: -amount_cents }.merge(dims) ])
  end

  def unpost_from_books
    LedgerPosting.unpost!(source: self, kind: "bill_payment")
  end
end
