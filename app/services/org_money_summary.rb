# frozen_string_literal: true

# Where one organization's money stands, for the superadmin org page: what
# CocoScout holds for it, what's on its way in or out, what it owes its
# payees, what it's been billed and what it paid CocoScout.
class OrgMoneySummary
  InFlight = Data.define(:label, :cents, :detail, :since)
  WITHDRAWAL_WORDS = { "pending" => "being sent", "sent" => "on its way to their bank",
                       "bank_rejected" => "their bank turned it down; it waits in their Stripe account" }.freeze

  attr_reader :organization

  def initialize(organization)
    @organization = organization
  end

  def held_cents = OrgCashEntry.balance_cents(organization)
  def balance = @balance ||= CocoScoutBalance.summary(organization)

  # Money moving right now: a run's bank debit on its way in, a run paying
  # its payees, a withdrawal on its way to (or turned down by) their bank.
  def in_flight
    rows = []
    organization.payout_batches.where(status: "funding").find_each do |batch|
      debit = [ batch.total_cents - batch.held_cents - batch.credit_applied_cents - batch.balance_applied_cents, 0 ].max
      rows << InFlight.new(label: "Payout run ##{batch.id}: bank debit on its way in", cents: debit,
                           detail: "#{fmt(batch.total_cents)} run; #{fmt(batch.balance_applied_cents)} from their balance", since: batch.updated_at)
    end
    organization.payout_batches.where(status: %w[funded processing partially_paid]).find_each do |batch|
      unpaid = batch.items.where(status: PayoutBatch::RETRYABLE_ITEM_STATUSES).sum(:amount_cents)
      next unless unpaid.positive?

      rows << InFlight.new(label: "Payout run ##{batch.id}: payees not paid yet", cents: unpaid, detail: batch.display_status, since: batch.updated_at)
    end
    organization.balance_withdrawals.where(status: WITHDRAWAL_WORDS.keys).order(:created_at).each do |withdrawal|
      rows << InFlight.new(label: "Withdrawal: #{WITHDRAWAL_WORDS[withdrawal.status]}", cents: withdrawal.amount_cents,
                           detail: withdrawal.error, since: withdrawal.created_at)
    end
    rows
  end

  # What it owes each payee (performers, staff, contractors) that hasn't
  # been paid yet.
  def owed_to_payees
    sums = PayoutLedgerEntry.where(organization: organization).group(:payee_type, :payee_id).sum(:amount_cents).select { |_, cents| cents.positive? }
    payees = sums.keys.group_by(&:first).flat_map { |type, keys| type.constantize.where(id: keys.map(&:last)).to_a }.index_by { |p| [ p.class.polymorphic_name, p.id ] }
    sums.filter_map { |key, cents| [ payees[key], cents ] if payees[key] }.sort_by { |_, cents| -cents }
  end

  def usage_this_month(month = Date.current)
    { performers: PerformerActivation.where(organization: organization).for_month(month).count,
      staff: StaffActivation.where(organization: organization).for_month(month).count }
  end

  def invoices
    BillingInvoice.where(organization: organization).newest_first
  end

  # What it paid CocoScout, by month (newest first), by kind.
  def paid_cocoscout_by_month(months: 12)
    since = (Date.current - (months - 1).months).beginning_of_month
    zone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
    CocoScoutLedgerEntry.where(organization: organization, entry_type: CocoScoutLedgerEntry.types_in(:income))
                        .where(occurred_at: since.beginning_of_day..)
                        .group(Arel.sql("DATE_TRUNC('month', occurred_at AT TIME ZONE 'UTC' AT TIME ZONE #{zone})"), :entry_type)
                        .sum(:amount_cents)
                        .each_with_object(Hash.new { |h, k| h[k] = {} }) { |((month, type), cents), out| out[month.to_date][type] = cents }
                        .sort.reverse.to_h
  end

  # Every movement of its CocoScout balance, newest first, with the balance
  # after each.
  def ledger(limit: 100)
    entries = OrgCashEntry.where(organization: organization).order(occurred_at: :desc, id: :desc).limit(limit).to_a
    running = held_cents
    entries.map do |entry|
      after = running
      running -= entry.amount_cents
      [ entry, after ]
    end
  end

  def books_mismatches
    BooksReconciliation.check(organization)
  end

  private

  def fmt(cents)
    ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)
  end
end
