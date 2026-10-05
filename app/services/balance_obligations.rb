# frozen_string_literal: true

# What the theater's CocoScout balance will be asked to pay soon, so the
# Balance page can say how much is safe to withdraw ("smart withdrawal"):
# keep this much here and the coming payouts go out the same day, with no
# bank debit to wait on.
#
#   - the open payout run (what it needs after held money and credit);
#   - approved staff hours not on a run yet (priced the way runs price them);
#   - money owed to payees that isn't on a run yet;
#   - contract payments the theater owes in the next two weeks.
#
# Shows that haven't happened aren't estimated: their pay isn't owed yet.
class BalanceObligations
  HORIZON = 14.days

  Item = Data.define(:label, :cents)

  def self.items(organization)
    [
      Item.new("Your open payout run", BalanceWithdrawalService.open_run_need_cents(organization)),
      Item.new("Approved staff hours not yet paid", staff_hours_cents(organization)),
      Item.new("Owed to performers and others, not yet on a run", owed_not_staged_cents(organization)),
      Item.new("Contract payments due in the next two weeks", contract_payments_due_cents(organization))
    ].select { |item| item.cents.positive? }
  end

  def self.total_cents(organization)
    items(organization).sum(&:cents)
  end

  # Spendable money beyond what's coming due.
  def self.safe_to_withdraw_cents(organization)
    [ CocoScoutBalance.available_cents(organization) - total_cents(organization), 0 ].max
  end

  def self.staff_hours_cents(organization)
    entries = StaffTimeEntry.approved.where(organization_id: organization.id).pluck(:person_id, :id).group_by(&:first)
    return 0 if entries.empty?

    members = organization.organization_staff_members.where(person_id: entries.keys).index_by(&:person_id)
    entries.sum do |person_id, rows|
      member = members[person_id]
      member ? StaffPayRunService.worked_cents(organization: organization, member: member, time_entry_ids: rows.map(&:last)) : 0
    end
  end

  def self.owed_not_staged_cents(organization)
    staged = PayoutBatchService.committed_by_payee(organization)
    organization.payout_balances_by_payee.sum { |key, cents| [ cents - staged.fetch(key, 0), 0 ].max }
  end

  def self.contract_payments_due_cents(organization)
    ContractPayment.direction_outgoing.status_pending.joins(:contract)
                   .where(contracts: { organization_id: organization.id })
                   .where(due_date: ..HORIZON.from_now.to_date)
                   .sum(&:amount_cents)
  end

  private_class_method :staff_hours_cents, :owed_not_staged_cents, :contract_payments_due_cents
end
