# frozen_string_literal: true

# Adds staff pay to the organization's open "staff_pay" payout run — the same
# accumulate-then-pay model as performer runs. The manager enters hours (and any
# bonus / reimbursement / tips) per staff member; each visit appends to the one
# open staffing run, which is funded and paid later from the payout-runs page (on
# its own schedule, separate from performers).
#
# One PayoutBatchItem per payee (their running total = one Stripe transfer), with
# a PayoutContribution per component (worked hours, bonus, reimbursement, tips) —
# so the run's detail view shows exactly what each person is being paid for. Each
# contribution posts an `earning` ledger entry (worker balance + history); the
# item posts the single debiting `payout` entry when paid.
#
# Cash tips are recorded on the pay grid for the record but are NOT routed here.
# Everyone with a positive amount is added, even without a connected bank — the
# run page warns about who isn't ready, and their transfer is skipped at pay time
# (leaving the balance owed), mirroring performer runs.
class StaffPayRunService
  Result = Struct.new(:batch, :added, keyword_init: true)

  # Worked-hours pay in cents. When specific approved time entries are pulled in,
  # each is paid at that role's rate (rate_cents_for resolves role rate → member
  # default); otherwise the manually entered hours are paid at the member default.
  def self.worked_cents(organization:, member:, hours: 0, time_entry_ids: nil)
    ids = Array(time_entry_ids).map(&:to_i).reject(&:zero?)
    return (member.hourly_rate_cents.to_i * hours.to_f).round if ids.empty?

    organization.staff_time_entries.for_person(member.person).where(id: ids)
                .includes(shift_assignment: { shift: :house_role })
                .sum { |entry| (member.rate_cents_for(entry.shift&.house_role).to_i * entry.hours.to_f).round }
  end

  # amount actually routed through Stripe (cash tips excluded).
  def self.payable_cents(worked_cents:, bonus_cents: 0, reimbursement_cents: 0, tips_cents: 0)
    worked_cents.to_i + bonus_cents.to_i + reimbursement_cents.to_i + tips_cents.to_i
  end

  # lines: array of hashes with keys :staff_member, :hours, :bonus_cents,
  # :reimbursement_cents, :tips_cents, :cash_tips_cents, :notes, :time_entry_ids.
  def self.add_lines!(organization:, created_by:, lines:, payday: nil)
    batch = nil
    added = 0

    ActiveRecord::Base.transaction do
      batch = PayoutBatch.open_for(organization, kind: "staff_pay", created_by: created_by)
      batch.update!(payday: payday) if payday.present? && batch.payday.blank?

      lines.each do |line|
        member = line[:staff_member]
        payee = member.person
        worked = worked_cents(
          organization: organization, member: member,
          hours: line[:hours], time_entry_ids: line[:time_entry_ids]
        )

        parts = contribution_parts(organization, member, line, worked)
        total = parts.sum { |p| p[:amount] }
        next if total <= 0

        item = batch.items.find_by(payee: payee) ||
               batch.items.create!(payee: payee, amount_cents: total, status: "pending")

        parts.each do |part|
          add_contribution!(batch, item, payee, label: part[:label], amount_cents: part[:amount], description: line[:notes])
        end
        item.update!(amount_cents: item.payout_contributions.sum(:amount_cents))

        tie_time_entries!(organization, payee, line[:time_entry_ids], batch)
        added += 1
      end

      batch.recalculate_total!
    end

    Result.new(batch: batch, added: added)
  end

  # The named components of a line, each becoming a contribution row. Cash tips
  # are intentionally excluded (recorded on the grid only, not sent through us).
  def self.contribution_parts(organization, member, line, worked)
    [
      { label: worked_label(organization, member, line), amount: worked.to_i },
      { label: "Bonus", amount: line[:bonus_cents].to_i },
      { label: "Reimbursement", amount: line[:reimbursement_cents].to_i },
      { label: "Tips", amount: line[:tips_cents].to_i }
    ].select { |p| p[:amount].positive? }
  end

  def self.worked_label(organization, member, line)
    ids = Array(line[:time_entry_ids]).map(&:to_i).reject(&:zero?)
    hours = if ids.any?
      organization.staff_time_entries.for_person(member.person).where(id: ids).sum(:hours)
    else
      line[:hours].to_f
    end
    formatted = ActiveSupport::NumberHelper.number_to_rounded(hours, precision: 2, strip_insignificant_zeros: true)
    "Worked hours (#{formatted}h)"
  end

  def self.add_contribution!(batch, item, payee, label:, amount_cents:, description: nil)
    contribution = PayoutContribution.create!(
      payout_batch: batch, payout_batch_item: item, payee: payee,
      amount_cents: amount_cents, label: label, description: description
    )
    PayoutLedgerEntry.post!(
      organization: batch.organization, payee: payee, entry_type: "earning",
      amount_cents: amount_cents, source: contribution,
      description: "Staff pay: #{label}", occurred_at: Time.current, category: "staffing"
    )
    contribution
  end

  # Attach the pulled-in worked-time entries to this batch so they leave the
  # unpaid pool and can't be paid again. Scoped to the org + payee for safety.
  def self.tie_time_entries!(organization, payee, ids, batch)
    ids = Array(ids).map(&:to_i).reject(&:zero?)
    return if ids.empty?

    # Paying implies approval — backfill approved_at for any that weren't
    # explicitly approved first.
    now = Time.current
    scope = organization.staff_time_entries.unpaid.for_person(payee).where(id: ids)
    scope.where(approved_at: nil).update_all(approved_at: now, updated_at: now)
    scope.update_all(payout_batch_id: batch.id, paid_at: now, updated_at: now)
  end
end
