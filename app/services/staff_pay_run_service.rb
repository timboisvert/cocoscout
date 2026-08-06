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

  # Worked-hours pay in cents. Hours always carry a role when one is known —
  # the role prices the work, the member default is only the fallback. A line
  # combines both kinds: included time entries (each paid at its own role's
  # rate — entry role, else the shift's) PLUS ad-hoc lines from the Hours modal
  # (each `{ hours:, house_role: }` paid at its role's rate; the legacy
  # hours/house_role kwargs still work for older callers).
  def self.worked_cents(organization:, member:, adhoc: nil, hours: 0, time_entry_ids: nil, house_role: nil)
    lines = Array(adhoc)
    lines = [ { hours: hours, house_role: house_role } ] if lines.empty? && hours.to_f.positive?
    adhoc_cents = lines.sum { |l| member.amount_cents_for(l[:house_role], hours: l[:hours].to_f) }

    ids = Array(time_entry_ids).map(&:to_i).reject(&:zero?)
    return adhoc_cents if ids.empty?

    entries = organization.staff_time_entries.for_person(member.person).where(id: ids)
                          .includes(:house_role, shift_assignment: { shift: :house_role })
                          .to_a

    # A flat role pays once per night, not once per entry — logging the same
    # security shift as two stints is still $50. Keyed by the shift where there
    # is one, and otherwise by the date, so two separate nights still pay twice.
    flat, hourly = entries.partition { |e| e.effective_house_role&.flat? }
    flat_cents = flat.uniq { |e| [ e.effective_house_role&.id, e.shift_assignment_id || e.started_at.to_date ] }
                     .sum { |e| member.amount_cents_for(e.effective_house_role, hours: e.hours) }
    hourly_cents = hourly.sum { |e| member.amount_cents_for(e.effective_house_role, hours: e.hours) }

    flat_cents + hourly_cents + adhoc_cents
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
        # Normalize the legacy single hours/house_role shape into ad-hoc lines
        # so the rest of the pipeline only ever sees one format.
        line[:adhoc] = normalize_adhoc(line)
        worked = worked_cents(
          organization: organization, member: member,
          adhoc: line[:adhoc], time_entry_ids: line[:time_entry_ids]
        )

        parts = contribution_parts(organization, member, line, worked)
        # Cash tips are recorded alongside but never paid, so a person joins the
        # run only when they have a payable amount.
        payable_total = parts.reject { |p| p[:excluded] }.sum { |p| p[:amount] }
        next if payable_total <= 0

        item = batch.items.find_by(payee: payee) ||
               batch.items.create!(payee: payee, amount_cents: payable_total, status: "pending")

        parts.each do |part|
          add_contribution!(batch, item, payee, label: part[:label], amount_cents: part[:amount],
                            description: line[:notes], excluded_from_payout: part[:excluded],
                            worksheet: part[:worksheet], details: part[:details])
        end
        item.update!(amount_cents: item.payout_contributions.payable.sum(:amount_cents))

        tie_time_entries!(organization, payee, line[:time_entry_ids], batch)
        added += 1
      end

      batch.recalculate_total!
    end

    Result.new(batch: batch, added: added)
  end

  # The named components of a line, each becoming a contribution row. Card tips
  # route through Stripe; cash tips are recorded-only (excluded_from_payout) —
  # kept as a permanent part of the run's record but never paid. Tips and cash
  # tips carry their per-day worksheet breakdown for backward traceability.
  def self.contribution_parts(organization, member, line, worked)
    # The ad-hoc "hours|role_id" pairs ride on the worked contribution so a
    # discarded draft run can rebuild the Pay People draft exactly as entered.
    adhoc_pairs = Array(line[:adhoc]).map { |l| "#{l[:hours]}|#{l[:house_role]&.id}" }
    worked_details = adhoc_pairs.any? ? { "adhoc" => adhoc_pairs } : nil
    [
      { label: worked_label(organization, member, line), amount: worked.to_i, excluded: false, details: worked_details },
      { label: "Bonus", amount: line[:bonus_cents].to_i, excluded: false },
      { label: "Reimbursement", amount: line[:reimbursement_cents].to_i, excluded: false },
      { label: "Tips", amount: line[:tips_cents].to_i, excluded: false, worksheet: line[:tips_worksheet] },
      { label: "Cash tips (recorded)", amount: line[:cash_tips_cents].to_i, excluded: true, worksheet: line[:cash_tips_worksheet] }
    ].select { |p| p[:amount].positive? }
  end

  def self.normalize_adhoc(line)
    adhoc = Array(line[:adhoc])
    return adhoc if adhoc.any?

    line[:hours].to_f.positive? ? [ { hours: line[:hours].to_f, house_role: line[:house_role] } ] : []
  end

  def self.worked_label(organization, member, line)
    ids = Array(line[:time_entry_ids]).map(&:to_i).reject(&:zero?)
    adhoc = Array(line[:adhoc])
    # Included entries + all ad-hoc lines — the line's total worked time.
    hours = adhoc.sum { |l| l[:hours].to_f }
    hours += organization.staff_time_entries.for_person(member.person).where(id: ids).sum(:hours).to_f if ids.any?
    formatted = ActiveSupport::NumberHelper.number_to_rounded(hours, precision: 2, strip_insignificant_zeros: true)
    # A single pure ad-hoc line under a chosen role names the role on the
    # record; anything mixed stays generic (each entry carries its own role).
    role_suffix = ids.empty? && adhoc.size == 1 && adhoc.first[:house_role] ? " as #{adhoc.first[:house_role].name}" : ""
    "Worked hours (#{formatted}h#{role_suffix})"
  end

  def self.add_contribution!(batch, item, payee, label:, amount_cents:, description: nil, excluded_from_payout: false, worksheet: nil, details: nil)
    contribution = PayoutContribution.create!(
      payout_batch: batch, payout_batch_item: item, payee: payee,
      amount_cents: amount_cents, label: label, description: description,
      excluded_from_payout: excluded_from_payout, worksheet: worksheet.presence, details: details.presence
    )
    # Recorded-only lines (cash tips) must not add to the worker's owed balance —
    # they're already in hand, so no earning entry is posted.
    unless excluded_from_payout
      PayoutLedgerEntry.post!(
        organization: batch.organization, payee: payee, entry_type: "earning",
        amount_cents: amount_cents, source: contribution,
        description: "Staff pay: #{label}", occurred_at: Time.current, category: "staffing"
      )
    end
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
