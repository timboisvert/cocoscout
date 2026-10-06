# frozen_string_literal: true

# CocoScout's own invoice for what it billed an organization: its Pro plan or
# a month's usage. Stripe still does the billing and charging (BillingInvoice
# mirrors each bill); this is the document, with Stripe's invoice number so a
# charge never carries two numbers. A usage invoice names the people it
# counted: staff with a paid shift and performers with a paid show that month.
class CocoScoutInvoice
  def self.document(billing_invoice)
    new(billing_invoice).document
  end

  def self.filename(billing_invoice)
    "CocoScout invoice #{billing_invoice.number.presence || billing_invoice.id} (#{billing_invoice.title}).pdf"
  end

  def initialize(billing_invoice)
    @bill = billing_invoice
    @organization = billing_invoice.organization
  end

  def document
    InvoiceDocument.new(
      number: @bill.number.presence || "CS-#{@bill.id}",
      issued_on: @bill.billed_on || @bill.created_at.to_date,
      seller: CocoScoutIdentity.party,
      bill_to: @organization.invoice_seller,
      reference: [ [ "Bill", @bill.title ], [ "Period", period ] ],
      items: items,
      total_cents: @bill.amount_due_cents,
      status: status,
      status_line: status_line,
      notes: notes,
      sections: people,
      footer: "#{CocoScoutIdentity::BRAND} is a service of #{CocoScoutIdentity::LEGAL_NAME}. Questions about this invoice: #{CocoScoutIdentity::EMAIL}.",
      logo: CocoScoutIdentity::LOGO_PATH
    )
  end

  private

  # A Pro bill's dates. A usage bill's title already names its month.
  def period
    return nil unless @bill.period_start && @bill.period_end && @bill.kind != "usage"

    "#{@bill.period_start.to_date.strftime('%b %-d, %Y')} to #{@bill.period_end.to_date.strftime('%b %-d, %Y')}"
  end

  # Stripe's lines, then any account credit Stripe applied, so the lines add up
  # to what was charged.
  def items
    lines = Array(@bill.lines).reject { |line| line["amount_cents"].to_i.zero? }.map do |line|
      detail = "Brings the bill to what CocoScout's records show for the month." if line["description"].to_s.start_with?(UsageInvoiceCorrection::PREFIX)
      InvoiceDocument::Line.new(description: line["description"], detail: detail, amount_cents: line["amount_cents"])
    end
    credit = @bill.amount_due_cents - lines.sum(&:amount_cents)
    lines << InvoiceDocument::Line.new(description: "Credit from your CocoScout account", amount_cents: credit) if credit.negative?
    lines
  end

  def status
    return :paid if @bill.status == "paid"
    return :void if @bill.status == "void"
    return :failed if @bill.failed?
    return :collecting if @bill.collecting?

    :due
  end

  def status_line
    case status
    when :paid then "Paid#{" #{@bill.paid_at.strftime('%B %-d, %Y')}" if @bill.paid_at}"
    when :void then "Void"
    when :failed then [ "Payment failed", @bill.failure_message ].compact_blank.join(": ")
    else @bill.status_label
    end
  end

  def notes
    return [] if status.in?(%i[paid void])

    [ "Charged automatically to the payment method on file with CocoScout. Nothing to do." ]
  end

  # The people a usage bill counted, by name.
  def people
    month = @bill.kind == "usage" && @bill.covered_month
    return [] unless month

    staff = names(StaffActivation, month)
    performers = names(PerformerActivation, month)
    [
      [ "Staff with a paid shift in #{month.strftime('%B %Y')} (#{staff.size} × #{dollars(StaffBillingService::PER_ACTIVE_STAFF_CENTS)})", staff ],
      [ "Performers paid for a show in #{month.strftime('%B %Y')} (#{performers.size} × #{dollars(PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS)})", performers ]
    ]
  end

  def names(model, month)
    model.where(organization: @organization).for_month(month).includes(:person).map { |a| a.person&.name.to_s }.compact_blank.sort
  end

  def dollars(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)
  end
end
