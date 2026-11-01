# frozen_string_literal: true

# One organization's usage for one month, as its bill will charge it: the
# staff ($5) and everyone else ($3) counted (StaffActivation and
# PerformerActivation, kept to UsageRules), its bank debits and any beyond the
# free ones ($5 each), what it withdrew (0.25% on the part over $5,000), and
# the bill that carries the month once there is one.
class UsageMonth
  attr_reader :organization, :month

  def initialize(organization, month = Date.current)
    @organization = organization
    @month = month.to_date.beginning_of_month
  end

  def by_payment? = UsageRules.by_payment?(month)

  def staff
    @staff ||= Person.where(id: StaffActivation.where(organization: organization).for_month(month).select(:person_id)).order(:name).to_a
  end

  def others
    @others ||= Person.where(id: PerformerActivation.where(organization: organization).for_month(month).select(:person_id)).order(:name).to_a
  end

  def staff_cents = staff.size * StaffBillingService::PER_ACTIVE_STAFF_CENTS
  def others_cents = others.size * PerformerBillingService::PER_ACTIVE_PERFORMER_CENTS

  def bank_debits
    @bank_debits ||= UsageRules.bank_debits(organization, month)
  end

  def free_debits_left = [ UsageRules::FREE_BANK_DEBITS - bank_debits.size, 0 ].max
  def extra_debits = by_payment? ? [ bank_debits.size - UsageRules::FREE_BANK_DEBITS, 0 ].max : 0
  def extra_debits_cents = extra_debits * UsageRules::EXTRA_BANK_DEBIT_CENTS

  def withdrawn_cents
    @withdrawn_cents ||= UsageRules.withdrawn_cents(organization, month)
  end

  def withdrawal_fee_cents = UsageRules.withdrawal_fee_cents(organization, month, withdrawn_cents)
  def free_withdrawal_left_cents = [ UsageRules::FREE_WITHDRAWAL_CENTS - withdrawn_cents, 0 ].max

  # Pro for the month, when it's paid on this bill.
  def pro_cents = UsageRules.pro_cents(organization, month)

  def usage_cents = staff_cents + others_cents + extra_debits_cents + withdrawal_fee_cents
  def total_cents = pro_cents + usage_cents

  # The bill for the month: the usage bill whose period it is (the first, if
  # a month ever had two).
  def bill
    return @bill if defined?(@bill)

    @bill = organization.billing_invoices.where(kind: "usage").where.not(status: "void").order(:id)
                        .find { |invoice| invoice.covered_month == month }
  end

  # When the month is billed: the 1st of the next month.
  def billed_on = month.next_month
end
