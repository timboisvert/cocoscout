# frozen_string_literal: true

# An organization's invoice (plan D2), numbered in its one sequence
# (SG-0014) and never reused. Two kinds share the number, the page and PDF
# (InvoiceDocument), the sending (InvoiceDelivery) and the void:
#
#   standalone  an invoice to anyone: a sponsor, a school, a group buying a
#               block of seats. It keeps its own lines, due date and
#               payments. They pay by card or bank on its page
#               (/pay/invoice/:token), or the organization records the check.
#               On the books the unpaid part sits as Money owed to you
#               against the income category (counted when earned, no cash
#               date); each payment is that much income arriving where it
#               arrived (counted when it moved).
#   contract    the invoice for one payment someone owes under a contract.
#               The payment keeps the money and its own place on the books;
#               this row is its paper. Its page is the payment's pay page
#               (/pay/contract/:token). The number is issued the first time
#               anyone opens it (Invoice.for!), and it outlives a payment
#               that was combined into another, removed or cancelled, void.
#
# What an invoice says (what's due, when, from whom, whether it's paid) is
# its terms: Invoice::OwnTerms reads this row, Invoice::ContractTerms reads
# the payment.
class Invoice < ApplicationRecord
  KINDS = %w[standalone contract].freeze
  STATUSES = %w[open paid void].freeze
  REMINDERS = { "before_and_overdue" => "3 days before, and when overdue", "overdue" => "Only when overdue", "none" => "None" }.freeze
  BANK_TRANSFER_MINIMUM_CENTS = 50_000
  # The reminders that go by themselves (InvoiceRemindersJob): this many days
  # before it's due, and once in the days after it.
  REMIND_BEFORE = 3
  REMIND_OVERDUE_WITHIN = 14

  include BooksLock::Validation
  refuses_locked_books_on :issued_on, unless: :contract?

  belongs_to :organization
  belongs_to :contract_payment, optional: true, inverse_of: :invoice
  belongs_to :combined_into_payment, class_name: "ContractPayment", optional: true
  belongs_to :production, optional: true
  belongs_to :show, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :invoice_lines, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :invoice
  has_many :invoice_payments, dependent: :destroy
  accepts_nested_attributes_for :invoice_lines, allow_destroy: true, reject_if: ->(attrs) { attrs["description"].blank? && attrs["unit"].blank? && attrs["unit_cents"].blank? }

  validates :number, presence: true, uniqueness: { scope: :organization_id }
  validates :kind, inclusion: { in: KINDS }
  validates :prefix, :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :reminders, inclusion: { in: REMINDERS.keys }
  # Its own facts, which a contract payment's invoice reads from the payment.
  with_options unless: :contract? do
    validates :bill_to_name, :due_on, :category_key, presence: true
    validates :bill_to_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    validate :has_a_line
  end

  before_validation :assign_number, on: :create
  before_validation :total_lines, unless: :contract?
  # A contract payment posts itself; its invoice has nothing of its own to post.
  after_commit :post_to_books, on: %i[create update], unless: :contract?
  after_commit :unpost_from_books, on: :destroy, unless: :contract?

  scope :standalone, -> { where(kind: "standalone") }
  scope :for_contracts, -> { where(kind: "contract") }
  scope :open, -> { where(status: "open") }
  scope :live, -> { where.not(status: "void") }
  scope :by_due, -> { order(:due_on, :id) }

  # This payment's invoice, issuing it if it has none yet.
  def self.for!(payment)
    payment.invoice || issue!(payment)
  end

  # The organization's counter row is locked while the number is taken, so
  # two invoices issued at once can't get the same one, and a payment opened
  # twice at once gets one invoice.
  def self.issue!(payment)
    organization = payment.contract.organization
    invoice = transaction do
      organization.lock!
      find_by(contract_payment_id: payment.id) ||
        create!(kind: "contract", organization: organization, contract_payment: payment, payment_token: payment.payment_token!, issued_on: Date.current)
    end
    payment.association(:invoice).target = invoice
    invoice
  rescue ActiveRecord::RecordNotUnique
    find_by!(contract_payment_id: payment.id)
  end

  def contract? = kind == "contract"
  def open? = status == "open"
  def paid? = status == "paid"
  def void? = status == "void"
  # Its own due date; a contract payment's invoice has none (ask its state).
  def overdue? = open? && due_on.present? && due_on < Date.current
  def unpaid_cents = [ total_cents - paid_cents, 0 ].max
  def amount = total_cents / 100.0
  def display_number = "#{prefix}-#{number.to_s.rjust(4, '0')}"
  def filename = "Invoice #{display_number}.pdf"
  def kind_label = "Invoice"

  # What it says, read from wherever its money is kept.
  def terms = contract? ? ContractTerms.new(self) : OwnTerms.new(self)

  # Where it stands, for the page, the PDF and the lists: :due, :overdue,
  # :paid or :void.
  def state = terms.state

  def category_label = MoneyCategories.label_for(category_key, :income, organization: organization)
  def category_account = MoneyCategories.account_for(category_key, :income, organization: organization)

  def title = "#{display_number}, #{bill_to_name}"

  def payment_token!
    return payment_token if payment_token.present?

    update_columns(payment_token: SecureRandom.urlsafe_base64(24))
    payment_token
  end

  # Whether reminders go by themselves at all: an invoice the organization
  # wrote, still open, that was emailed to someone. One that was never sent
  # gets none: "a reminder" of something they never got would be the first
  # they heard of it.
  def reminds_itself?
    !contract? && open? && reminders != "none" && sent_count.positive? && sent_at.present? && due_on.present? && bill_to_email.present?
  end

  # The day the next reminder goes by itself, or nil when none will. Each
  # goes once, and any send counts: one sent inside the three days before
  # it's due gets no "before" reminder, and one a manager sent again after
  # the due date gets no "overdue" one. Read in the zone the caller is in.
  def next_reminder_on(today = Date.current)
    return nil unless reminds_itself?

    sent_on = sent_at.to_date
    before = due_on - REMIND_BEFORE
    return [ before, today ].max if reminders == "before_and_overdue" && sent_on < before && today < due_on
    return [ due_on + 1, today ].max if sent_on <= due_on && today <= due_on + REMIND_OVERDUE_WITHIN

    nil
  end

  def reminder_due?(today = Date.current) = next_reminder_on(today) == today

  def collectable_online? = open? && unpaid_cents.positive? && (pay_by_card || pay_by_bank)
  def bank_transfer_allowed? = pay_by_bank && unpaid_cents >= BANK_TRANSFER_MINIMUM_CENTS

  # Ways to pay, in a sentence for the invoice.
  def ways_to_pay
    ways = []
    ways << "card" if pay_by_card
    ways << "bank transfer" if pay_by_bank
    ways << "check" if pay_by_check
    ways.to_sentence
  end

  # A payment that arrived: recorded by hand, or collected on the pay page.
  def receive!(on:, amount_cents:, via:, by: nil, reference: nil, memo: nil)
    raise ArgumentError, "nothing to receive" unless open? && amount_cents.positive?

    payment = nil
    transaction do
      payment = invoice_payments.create!(organization: organization, on: on, amount_cents: [ amount_cents, unpaid_cents ].min, via: via,
                                         recorded_by: by, reference: reference, memo: memo)
      new_paid = paid_cents + payment.amount_cents
      update!(paid_cents: new_paid, status: (new_paid >= total_cents ? "paid" : "open"), paid_on: (new_paid >= total_cents ? on : nil))
    end
    payment
  end

  # combined_into: the contract payment that took this one's in, so an old
  # link to it can say what became of it.
  def void!(reason, combined_into: nil)
    return if void?

    update!(status: "void", voided_at: Time.current, void_reason: reason.presence, combined_into_payment: combined_into)
  end

  def for_label
    return nil unless production

    show ? "#{production.name}, #{show.date_and_time.strftime('%b %-d, %Y')}" : production.name
  end

  # The invoice as its page and PDF draw it (InvoiceDocument, shared with
  # CocoScout's own bills), so the two can never disagree. The PDF also
  # prints the pay link (the page has the button).
  def document(pdf: false)
    said = terms
    InvoiceDocument.new(
      number: display_number,
      issued_on: issued_on,
      due_on: said.state.in?(%i[due overdue]) ? said.due_on : nil,
      seller: organization.invoice_seller,
      bill_to: said.bill_to,
      reference: said.reference,
      items: said.items,
      total_cents: said.total_cents,
      status: said.state,
      status_line: status_line,
      notes: said.notes(pdf: pdf),
      footer: "Online payments are processed by #{CocoScoutIdentity::BRAND} (#{CocoScoutIdentity::LEGAL_NAME}) for #{organization.name}.",
      logo: organization.logo
    )
  end

  # "Paid October 3, 2026 · Check · #1042"
  def status_line
    said = terms
    money = ActiveSupport::NumberHelper.number_to_currency(said.amount_due_cents / 100.0) if said.state.in?(%i[due overdue])
    case said.state
    when :void then [ "Void", void_reason ].compact_blank.join(": ")
    when :paid then said.paid_line
    when :overdue then "Amount due: #{money}, was due #{said.due_on.strftime('%B %-d, %Y')}"
    else "Amount due: #{money} by #{said.due_on.strftime('%B %-d, %Y')}"
    end
  end

  def journal_entry
    JournalEntry.live.find_by(source_type: self.class.polymorphic_name, source_id: id, kind: "invoice")
  end

  def post_to_books
    dims = { production: production, show: show }
    remainder = void? ? 0 : unpaid_cents
    lines = remainder.positive? ? [ { account: :owed_to_you, amount_cents: remainder, memo: bill_to_name }.merge(dims), { account: category_account, amount_cents: -remainder, memo: bill_to_name }.merge(dims) ] : []
    LedgerPosting.post!(organization: organization, source: self, kind: "invoice", entry_date: issued_on, cash_date: nil, memo: "Invoice #{display_number}: #{bill_to_name}", lines: lines)
  end

  def unpost_from_books
    LedgerPosting.unpost!(source: self, kind: "invoice")
  end

  private

  def has_a_line
    errors.add(:base, "Add at least one line") if invoice_lines.reject(&:marked_for_destruction?).empty?
  end

  def total_lines
    # The lines' own callbacks run after this one, so total their amounts here.
    self.total_cents = invoice_lines.reject(&:marked_for_destruction?).sum { |l| l.compute_amount }
  end

  # The organization's one sequence, shared with contract invoices and
  # locked while the number is taken.
  def assign_number
    return if number.present?

    organization.with_lock do
      self.number = organization.invoice_next_number
      self.prefix ||= organization.invoice_prefix_or_default
      organization.update_columns(invoice_next_number: number + 1)
    end
  end
end
