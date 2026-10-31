# frozen_string_literal: true

# An invoice to anyone (plan D2): a sponsor, a school, a group buying a block
# of seats. Numbered in the organization's one sequence with its contract
# invoices (SG-0014). They pay by card or bank on a page of their own
# (/pay/invoice/:token), or the organization records the check when it comes.
#
# On the books: the unpaid part sits as Money owed to you against the
# income category (counted when earned, no cash date); each payment is that
# much income arriving where it arrived (counted when it moved).
class Invoice < ApplicationRecord
  STATUSES = %w[open paid void].freeze
  REMINDERS = { "before_and_overdue" => "3 days before, and when overdue", "overdue" => "Only when overdue", "none" => "None" }.freeze
  BANK_TRANSFER_MINIMUM_CENTS = 50_000

  belongs_to :organization
  belongs_to :production, optional: true
  belongs_to :show, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :invoice_lines, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :invoice
  has_many :invoice_payments, dependent: :destroy
  accepts_nested_attributes_for :invoice_lines, allow_destroy: true, reject_if: ->(attrs) { attrs["description"].blank? && attrs["unit"].blank? && attrs["unit_cents"].blank? }

  validates :number, presence: true, uniqueness: { scope: :organization_id }
  validates :prefix, :bill_to_name, :issued_on, :due_on, :category_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :reminders, inclusion: { in: REMINDERS.keys }
  validates :bill_to_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :has_a_line

  before_validation :assign_number, on: :create
  before_validation :total_lines
  after_commit :post_to_books, on: %i[create update]
  after_commit :unpost_from_books, on: :destroy

  scope :open, -> { where(status: "open") }
  scope :live, -> { where.not(status: "void") }
  scope :by_due, -> { order(:due_on, :id) }

  def open? = status == "open"
  def paid? = status == "paid"
  def void? = status == "void"
  def overdue? = open? && due_on < Date.current
  def unpaid_cents = [ total_cents - paid_cents, 0 ].max
  def amount = total_cents / 100.0
  def display_number = "#{prefix}-#{number.to_s.rjust(4, '0')}"
  def filename = "Invoice #{display_number}.pdf"
  def state = void? ? :void : (paid? ? :paid : (overdue? ? :overdue : :due))
  def kind_label = "Invoice"

  def category_label = MoneyCategories.label_for(category_key, :income, organization: organization)
  def category_account = MoneyCategories.account_for(category_key, :income, organization: organization)

  def title = "#{display_number}, #{bill_to_name}"

  def payment_token!
    return payment_token if payment_token.present?

    update_columns(payment_token: SecureRandom.urlsafe_base64(24))
    payment_token
  end

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

  def void!(reason)
    update!(status: "void", voided_at: Time.current, void_reason: reason.presence)
  end

  def for_label
    return nil unless production

    show ? "#{production.name}, #{show.date_and_time.strftime('%b %-d, %Y')}" : production.name
  end

  # The invoice as its page and PDF draw it (InvoiceDocument, shared with
  # contract invoices and CocoScout's own bills).
  def document(pdf: false)
    InvoiceDocument.new(
      number: display_number,
      issued_on: issued_on,
      due_on: state.in?(%i[due overdue]) ? due_on : nil,
      seller: organization.invoice_seller,
      bill_to: InvoiceDocument::Party.new(name: bill_to_name, lines: [ bill_to_attention.presence && "Attn. #{bill_to_attention}", *bill_to_address.to_s.split(/\r?\n/).map(&:strip) ].compact,
                                          email: bill_to_email),
      reference: [ [ "Production", production&.name ], [ "Event", show && "#{show.display_name}, #{show.date_and_time.strftime('%a %b %-d, %Y')}" ] ],
      items: invoice_lines.map { |l| InvoiceDocument::Line.new(description: l.description, detail: (l.quantity != 1 ? "#{l.quantity_label} × #{ActiveSupport::NumberHelper.number_to_currency(l.unit_cents / 100.0)}" : nil), amount_cents: l.amount_cents) },
      total_cents: total_cents,
      status: state,
      status_line: status_line,
      notes: notes(pdf: pdf),
      footer: "Online payments are processed by #{CocoScoutIdentity::BRAND} (#{CocoScoutIdentity::LEGAL_NAME}) for #{organization.name}.",
      logo: organization.logo
    )
  end

  def status_line
    money = ActiveSupport::NumberHelper.number_to_currency(unpaid_cents / 100.0)
    case state
    when :void then [ "Void", void_reason ].compact_blank.join(": ")
    when :paid then "Paid#{" #{paid_on.strftime('%B %-d, %Y')}" if paid_on}"
    when :overdue then "Amount due: #{money}, was due #{due_on.strftime('%B %-d, %Y')}"
    else "Amount due: #{money} by #{due_on.strftime('%B %-d, %Y')}"
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

  def notes(pdf:)
    note = organization.invoice_details_with_defaults["note"]
    return [ memo.presence, note ].compact_blank unless state.in?(%i[due overdue])

    check = pay_by_check ? "You can also pay by check to #{organization.invoice_seller.name}#{organization.invoice_seller.lines.any? ? ", #{organization.invoice_seller.lines.join(', ')}" : ''}." : nil
    return [ memo.presence, check, note ].compact_blank unless pdf

    url_options = Rails.application.config.action_mailer.default_url_options || { host: "localhost", port: 3000 }
    pay = collectable_online? ? "Pay online: #{Rails.application.routes.url_helpers.pay_invoice_url(token: payment_token!, **url_options)}" : nil
    [ memo.presence, pay, check, note ].compact_blank
  end

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
