# frozen_string_literal: true

# Money the organization owes someone and hasn't paid yet (Money → Bills,
# plan D1): the venue's rent, the lumber yard, the insurance. A bill goes on
# the books the day it arrives, and again the day it's paid.
#
# On the books: the unpaid part sits as the category's spending against
# Money you owe (counted when earned, with no cash date); each payment is
# that much spending paid from the account it came from (counted when it
# moved). Both ways of counting end up with the same total.
class Bill < ApplicationRecord
  REPEATS = { "none" => "Does not repeat", "monthly" => "Monthly", "quarterly" => "Every three months", "yearly" => "Yearly" }.freeze
  STATUSES = %w[open paid void].freeze
  VIA = { "bank" => [ "Bank", :bank ], "card" => [ "Credit card", :credit_card ], "door_cash" => [ "Door cash", :door_cash ], "check" => [ "Check", :bank ] }.freeze

  belongs_to :organization
  belongs_to :production, optional: true
  belongs_to :show, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :repeated_from, class_name: "Bill", optional: true
  has_many :bill_payments, dependent: :destroy
  has_one_attached :document

  validates :vendor_name, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :issued_on, :due_on, :category_key, presence: true
  validates :repeats, inclusion: { in: REPEATS.keys }
  validates :status, inclusion: { in: STATUSES }
  validate :acceptable_document

  before_validation { self.issued_on ||= Date.current }
  after_commit :post_to_books, on: %i[create update]
  after_commit :unpost_from_books, on: :destroy

  scope :open, -> { where(status: "open") }
  scope :paid, -> { where(status: "paid") }
  scope :live, -> { where.not(status: "void") }
  scope :by_due, -> { order(:due_on, :id) }
  scope :overdue, ->(on = Date.current) { open.where("due_on < ?", on) }

  def open? = status == "open"
  def paid? = status == "paid"
  def void? = status == "void"
  def overdue? = open? && due_on < Date.current
  def unpaid_cents = [ amount_cents - paid_cents, 0 ].max
  def amount = amount_cents / 100.0

  def amount=(value)
    self.amount_cents = (value.to_s.delete(",$ ").to_d * 100).round
  end

  def category_label = MoneyCategories.label_for(category_key, :spending, organization: organization)
  def category_account = MoneyCategories.account_for(category_key, :spending, organization: organization)

  def title = [ vendor_name, memo.presence ].compact.join(" · ")

  def for_label
    return "Nothing in particular" unless production

    show ? "#{production.name}, #{show.date_and_time.strftime('%b %-d, %Y')}" : production.name
  end

  # A payment, part or whole. Paying a repeating bill in full makes the next one.
  def pay!(on:, amount_cents:, via:, by: nil, reference: nil, memo: nil)
    raise ArgumentError, "nothing to pay" unless open? && amount_cents.positive?

    payment = nil
    transaction do
      payment = bill_payments.create!(organization: organization, on: on, amount_cents: [ amount_cents, unpaid_cents ].min, via: via,
                                      recorded_by: by, reference: reference, memo: memo)
      update!(paid_cents: paid_cents + payment.amount_cents, status: (paid_cents + payment.amount_cents >= self.amount_cents ? "paid" : "open"),
              paid_on: (paid_cents + payment.amount_cents >= self.amount_cents ? on : nil))
      repeat! if paid? && repeats != "none" && organization.bills.where(repeated_from: self).none?
    end
    payment
  end

  def void!(reason)
    update!(status: "void", voided_at: Time.current, void_reason: reason.presence)
  end

  # The next one in the series, dated a period later with this amount filled in.
  def repeat!
    step = { "monthly" => 1, "quarterly" => 3, "yearly" => 12 }.fetch(repeats)
    organization.bills.create!(vendor_name: vendor_name, vendor_email: vendor_email, amount_cents: amount_cents, issued_on: issued_on >> step, due_on: due_on >> step,
                               category_key: category_key, production: production, show: show, memo: memo, repeats: repeats,
                               repeated_from: self, created_by: created_by)
  end

  def journal_entry
    JournalEntry.live.find_by(source_type: self.class.polymorphic_name, source_id: id, kind: "bill")
  end

  def post_to_books
    dims = { production: production, show: show }
    remainder = void? ? 0 : unpaid_cents
    lines = remainder.positive? ? [ { account: category_account, amount_cents: remainder, memo: vendor_name }.merge(dims), { account: :you_owe, amount_cents: -remainder, memo: vendor_name }.merge(dims) ] : []
    LedgerPosting.post!(organization: organization, source: self, kind: "bill", entry_date: issued_on, cash_date: nil, memo: title, lines: lines)
  end

  def unpost_from_books
    LedgerPosting.unpost!(source: self, kind: "bill")
  end

  private

  def acceptable_document
    return unless document.attached?

    errors.add(:document, "must be a PDF, JPG or PNG") unless document.content_type.in?(%w[application/pdf image/jpeg image/png])
    errors.add(:document, "must be under 10 MB") if document.byte_size > 10.megabytes
  end
end
