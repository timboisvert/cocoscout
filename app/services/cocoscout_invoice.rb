# frozen_string_literal: true

# CocoScout's own invoice for what it billed an organization: its Pro plan or
# a month's usage. Stripe still does the billing and charging (BillingInvoice
# mirrors each bill); this is the document, with Stripe's invoice number so a
# charge never carries two numbers. A usage invoice names the people it
# counted: from November 2026 everyone paid through CocoScout that month
# (staff and everyone else), before that staff with a paid shift and
# performers with a paid show that month.
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

  # What the bill charges. A usage bill shows CocoScout's own count, the one
  # it bills by (UsageRules): the active staff and active performers of the
  # month it covers, at $5 and $3 each. Stripe's meter lines, and the
  # correction that brought them to this count (UsageInvoiceCorrection), stay
  # in Stripe: the theater never sees a meter it isn't billed by (Tim,
  # 2026-11-01). A Pro bill shows Stripe's lines. Then any account credit
  # Stripe applied, so the lines add up to what was charged.
  def items
    stripe_lines = Array(@bill.lines).reject { |line| line["amount_cents"].to_i.zero? }
    billed = stripe_lines.sum { |line| line["amount_cents"].to_i }
    lines = if usage_month
      usage_items(billed)
    else
      stripe_lines.map { |line| InvoiceDocument::Line.new(description: line["description"], amount_cents: line["amount_cents"]) }
    end
    credit = @bill.amount_due_cents - billed
    lines << InvoiceDocument::Line.new(description: "Credit from your CocoScout account", amount_cents: credit) if credit.negative?
    lines
  end

  # A usage bill's lines from CocoScout's count. The total Stripe billed
  # normally equals that count (the correction makes it so); when it doesn't,
  # one more line says by how much, so the lines still add up to the bill.
  def usage_items(billed)
    month = usage_month
    staff = StaffActivation.where(organization: @organization).for_month(month).count
    performers = PerformerActivation.where(organization: @organization).for_month(month).count
    debits = UsageRules.extra_bank_debits(@organization, month)
    counted = staff * StaffBillingService::PER_ACTIVE_STAFF_CENTS + performers * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS +
              debits * UsageRules::EXTRA_BANK_DEBIT_CENTS
    lines = UsageRules.by_payment?(month) ? paid_people_items(month, staff, performers) : worked_people_items(month, staff, performers)
    if debits.positive?
      lines << InvoiceDocument::Line.new(description: "#{debits} bank #{'debit'.pluralize(debits)} beyond the #{UsageRules::FREE_BANK_DEBITS} free × #{dollars(UsageRules::EXTRA_BANK_DEBIT_CENTS)}",
                                         detail: "Payout runs funded from your bank, and funds added from it, in #{month.strftime('%B %Y')}.",
                                         amount_cents: debits * UsageRules::EXTRA_BANK_DEBIT_CENTS)
    end
    difference = billed - counted
    if difference.positive?
      # A bill from before usage bills were checked against CocoScout's count
      # (usage:overbilled gives the difference back).
      lines << InvoiceDocument::Line.new(description: "Billed before this count was checked", amount_cents: difference,
                                         detail: "This bill was issued before CocoScout checked it against its own records.")
    elsif difference.negative?
      # Paid work that ended after Stripe drafted the bill: counted, not charged.
      lines << InvoiceDocument::Line.new(description: "Counted after this bill was issued", amount_cents: difference,
                                         detail: "Not charged on this bill.")
    end
    lines
  end

  # From November 2026: everyone paid through CocoScout that month (UsageRules).
  def paid_people_items(month, staff, others)
    lines = []
    if staff.positive?
      lines << InvoiceDocument::Line.new(description: "#{staff} #{'staff member'.pluralize(staff)} paid × #{dollars(StaffBillingService::PER_ACTIVE_STAFF_CENTS)}",
                                         detail: "Staff paid through CocoScout in #{month.strftime('%B %Y')}, counted once each.",
                                         amount_cents: staff * StaffBillingService::PER_ACTIVE_STAFF_CENTS)
    end
    if others.positive?
      lines << InvoiceDocument::Line.new(description: "#{others} #{others == 1 ? 'other person' : 'other people'} paid × #{dollars(PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS)}",
                                         detail: "Performers, contractors and everyone else paid through CocoScout in #{month.strftime('%B %Y')}, counted once each.",
                                         amount_cents: others * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS)
    end
    lines
  end

  # Through October 2026: everyone whose paid work happened that month.
  def worked_people_items(month, staff, performers)
    lines = []
    if staff.positive?
      lines << InvoiceDocument::Line.new(description: "#{staff} active #{'staff member'.pluralize(staff)} × #{dollars(StaffBillingService::PER_ACTIVE_STAFF_CENTS)}",
                                         detail: "Staff with a paid shift in #{month.strftime('%B %Y')}, counted once each.",
                                         amount_cents: staff * StaffBillingService::PER_ACTIVE_STAFF_CENTS)
    end
    if performers.positive?
      lines << InvoiceDocument::Line.new(description: "#{performers} active #{'performer'.pluralize(performers)} × #{dollars(PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS)}",
                                         detail: "Performers paid for a show in #{month.strftime('%B %Y')}, counted once each.",
                                         amount_cents: performers * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS)
    end
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
    month = usage_month
    return [] unless month

    [
      [ "Staff with a paid shift in #{month.strftime('%B %Y')}", names(StaffActivation, month) ],
      [ "Performers paid for a show in #{month.strftime('%B %Y')}", names(PerformerActivation, month) ]
    ]
  end

  # The month a usage bill covers; nil for any other bill.
  def usage_month
    return @usage_month if defined?(@usage_month)

    @usage_month = @bill.kind == "usage" ? @bill.covered_month : nil
  end

  def names(model, month)
    model.where(organization: @organization).for_month(month).includes(:person).map { |a| a.person&.name.to_s }.compact_blank.sort
  end

  def dollars(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)
  end
end
