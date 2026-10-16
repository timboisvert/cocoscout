# frozen_string_literal: true

# Everything My Payments shows one person, worked out once (Tim, 2026-10-10:
# after a few months of weekly pay the page was a list of everything ever
# earned, minus a lump "already paid out").
#
# In the payee's words (Tim, 2026-10-15): waiting for approval, approved, on
# its way, deposited. "Paid" on our side only means we sent it; the bank
# deposit follows a couple of business days later, so nothing here says paid
# until the payout provider says deposited.
#
#   coming   what hasn't been sent yet, by where it stands: going out now (a
#            run being funded: on its way), approved in the next payout run
#            (a draft), or approved but in no run yet (plus hours waiting for
#            approval). Every group is its line items, with charges taken out
#            of a share listed under it. The groups add up to the ledger
#            balance plus pending hours.
#   payments what's been sent, newest first: each payment with the lines it
#            covered and where it stands (on its way, deposited, or sent when
#            no word came), so a deposit says what it was for.
class MyPaymentsSummary
  # One thing they're paid for. deductions: Lines taken out of it (negative).
  Line = Data.define(:label, :detail, :cents, :deductions, :tag) do
    def initialize(detail: nil, deductions: [], tag: nil, **rest) = super(detail:, deductions:, tag:, **rest)
    def net_cents = cents + deductions.sum(&:cents)
  end

  # A batch of coming money: kind :on_its_way, :queued or :owed.
  Group = Data.define(:kind, :org, :when_text, :lines, :total_cents)

  # One payment sent. kind: run / show / hours / offset (the receipt kinds).
  # stage (run payments only): :on_its_way, :deposited or :sent
  # (PayoutBatchItem#deposit_stage); expected_on / deposited_on its dates.
  Payment = Data.define(:kind, :id, :org, :paid_at, :method, :cents, :offset_cents, :lines,
                        :stage, :expected_on, :deposited_on) do
    def initialize(stage: nil, expected_on: nil, deposited_on: nil, **rest) = super(stage:, expected_on:, deposited_on:, **rest)
    def title = lines.first&.label || "Payment"
    def more_count = [ lines.size - 1, 0 ].max
    def on_its_way? = stage == :on_its_way
  end

  HISTORY_LIMIT = 150
  # The payout provider wants a payee's date of birth and SSN last four once
  # their pay reaches $3,000, and pauses it until they're in; My Payments
  # says so from $2,000 (after-V1 #2).
  DETAILS_DUE_AT_CENTS = 300_000
  DETAILS_HEADS_UP_CENTS = 200_000

  attr_reader :person

  def initialize(person)
    @person = person
  end

  # --- Coming to you ---------------------------------------------------------

  def coming_groups
    @coming_groups ||= (run_groups + [ owed_group ].compact)
  end

  def coming_total_cents
    person.payout_balance_cents + pending_hours_cents
  end

  # Going out now (a run being funded) or sent and not yet deposited.
  def on_its_way_groups = coming_groups.select { |g| g.kind == :on_its_way }
  def on_its_way_payments = payments.select(&:on_its_way?)

  def on_its_way_cents
    on_its_way_groups.sum(&:total_cents) + on_its_way_payments.sum(&:cents)
  end

  # Approved or waiting for approval: not sent yet.
  def still_to_come_groups = coming_groups.reject { |g| g.kind == :on_its_way }

  def still_to_come_cents
    coming_total_cents - on_its_way_groups.sum(&:total_cents)
  end

  # Everything sent to their bank account through CocoScout, ever: what the
  # provider counts toward its $3,000.
  def sent_total_cents
    @sent_total_cents ||= PayoutBatchItem.where(payee: person, status: "paid").sum(:amount_cents)
  end

  # Time to add the two details: the account says more is coming due, and
  # their pay is close to the point the provider asks for it.
  def details_heads_up?
    person.payout_details_due && person.can_receive_payouts? && sent_total_cents >= DETAILS_HEADS_UP_CENTS
  end

  # Past payments: everything sent that isn't still on its way.
  def past_payments = payments.reject(&:on_its_way?)

  # --- Paid ------------------------------------------------------------------

  def payments
    @payments ||= (run_payments + show_payments + hours_payments + offset_payments)
                  .reject { |p| p.cents <= 0 && p.offset_cents.to_i <= 0 }
                  .sort_by { |p| p.paid_at&.to_time || Time.at(0) }.reverse.first(HISTORY_LIMIT)
  end

  def paid_total_cents
    payments.sum(&:cents)
  end

  def paid_this_year_cents(year = Date.current.year)
    payments.select { |p| p.paid_at&.year == year }.sum(&:cents)
  end

  # Payee words for a line written from the organization's side:
  # "Oct 8 — 50% to them" is their 50% share.
  def self.payee_words(text)
    text.to_s.sub(/(\d+(?:\.\d+)?%) to them\b/, 'your \1 share')
  end

  private

  # One group per payout run item still to be paid: funded runs first.
  def run_groups
    unpaid_items.sort_by { |i| [ i.payout_batch.in_flight? ? 0 : 1, i.payout_batch.created_at ] }.map do |item|
      batch = item.payout_batch
      lines = item_lines(item)
      when_text =
        if batch.in_flight?
          "Expected in your bank about #{batch.expected_deposit_range.first.strftime('%a, %b %-d')}"
        elsif batch.payday
          "Goes out #{batch.payday.strftime('%a, %b %-d')}"
        else
          "Goes out with the next payout run"
        end
      Group.new(kind: batch.in_flight? ? :on_its_way : :queued, org: batch.organization&.name,
                when_text: when_text, lines: lines, total_cents: item.amount_cents)
    end
  end

  # Earned but in no run yet, plus hours a manager hasn't approved. What the
  # lines can't explain (an advance still to repay, an old adjustment) is one
  # line of its own, so the group adds up to the balance.
  def owed_group
    staged = unpaid_items.sum(&:amount_cents)
    owed = person.payout_balance_cents - staged
    lines = unstaged_earning_lines
    rest = owed - lines.sum(&:cents)
    lines << Line.new(label: rest.negative? ? "Advances to repay" : "Earlier balance", cents: rest) unless rest.zero?
    lines += pending_hours_lines
    return nil if lines.empty?

    Group.new(kind: lines.all?(&:tag) ? :waiting : :owed, org: nil, when_text: nil, lines: lines,
              total_cents: owed + pending_hours_cents)
  end

  def unpaid_items
    @unpaid_items ||= PayoutBatchItem.where(payee: person, status: %w[pending failed])
                                     .joins(:payout_batch)
                                     .where(payout_batches: { status: PayoutBatchService::UNSETTLED_BATCH_STATUSES })
                                     .includes(payout_contributions: :source, payout_batch: :organization).to_a
  end

  # A run item's lines: each contribution, with the charges taken out of a
  # share under it. Anything the lines don't explain (the run netting an
  # advance) is its own line, so the lines add up to the deposit.
  def item_lines(item)
    contributions = item.payout_contributions.reject(&:excluded_from_payout)
    return [ Line.new(label: "Balance payout", cents: item.amount_cents) ] if contributions.empty?

    lines = PayoutContribution.with_deductions(contributions).map do |c, taken|
      Line.new(label: self.class.payee_words(c.label), detail: dates_text(c.covered_date_range), cents: c.amount_cents,
               deductions: taken.map { |d| Line.new(label: d.deduction_label, cents: d.amount_cents) })
    end
    rest = item.amount_cents - lines.sum(&:net_cents)
    lines << Line.new(label: rest.negative? ? "Advance repaid" : "Earlier balance", cents: rest) unless rest.zero?
    lines
  end

  # Show payouts worked out but not put in a run or paid by hand yet.
  def unstaged_earning_lines
    PayoutLedgerEntry.where(payee: person, entry_type: "earning", source_type: "ShowPayoutLineItem")
                     .includes(:organization, source: [ :payout_contribution, { show_payout: { show: :production } } ])
                     .order(:occurred_at).filter_map do |entry|
      li = entry.source
      next if li.nil? || li.paid? || li.payout_contribution.present? || entry.amount_cents.zero?

      show = li.show_payout&.show
      Line.new(label: show&.production&.name || "Show payout", detail: show&.date_and_time&.strftime("%B %-d, %Y"),
               cents: entry.amount_cents)
    end
  end

  # Hours awaiting a manager's approval, at their rate (an inactive
  # membership keeps its rates).
  def pending_hours_lines
    @pending_hours_lines ||= begin
      members = OrganizationStaffMember.where(person_id: person.id)
                                       .includes(staff_role_qualifications: :house_role).index_by(&:organization_id)
      StaffTimeEntry.where(person_id: person.id).pending
                    .includes(:organization, shift_assignment: { shift: :house_role }).chronological.map do |e|
        member = members[e.organization_id]
        cents = member ? member.amount_cents_for(e.effective_house_role, hours: e.hours) : 0
        Line.new(label: hours_label(e), detail: [ e.organization&.name, e.started_at&.strftime("%B %-d, %Y") ].compact.join(" · "),
                 cents: cents, tag: "Waiting for approval")
      end
    end
  end

  def pending_hours_cents
    pending_hours_lines.sum(&:cents)
  end

  def hours_label(entry)
    hrs = ActiveSupport::NumberHelper.number_to_rounded(entry.hours, precision: 2, strip_insignificant_zeros: true)
    role = entry.shift&.house_role&.name
    base = role ? "#{role} shift" : (entry.source == "manual" ? "Additional time" : "Shift")
    "#{base} · #{hrs}h"
  end

  # --- Payments --------------------------------------------------------------

  def run_payments
    PayoutBatchItem.where(payee: person, status: "paid")
                   .includes(payout_contributions: :source, payout_batch: :organization).map do |item|
      Payment.new(kind: "run", id: item.id, org: item.payout_batch.organization&.name, paid_at: item.paid_at,
                  method: "stripe", cents: item.amount_cents, offset_cents: nil, lines: item_lines(item),
                  stage: item.deposit_stage, expected_on: item.expected_deposit_date, deposited_on: item.deposited_at&.to_date)
    end
  end

  # Show payouts paid by hand (Zelle, Venmo…); run-paid ones are in their deposit.
  def show_payments
    ShowPayoutLineItem.where(payee: person, manually_paid: true)
                      .includes(show_payout: { show: { production: :organization } }).map do |li|
      show = li.show_payout&.show
      deductions = li.advance_deduction.to_f.positive? ? [ Line.new(label: "Advance repaid", cents: -(li.advance_deduction.to_d * 100).round) ] : []
      Payment.new(kind: "show", id: li.id, org: show&.production&.organization&.name, paid_at: li.paid_at || li.manually_paid_at,
                  method: li.payment_method, cents: (li.net_amount.to_d * 100).round, offset_cents: nil,
                  lines: [ Line.new(label: show&.production&.name || "Show payout", detail: show&.date_and_time&.strftime("%B %-d, %Y"),
                                    cents: (li.amount.to_d * 100).round, deductions: deductions) ])
    end
  end

  # Staff hours settled outside CocoScout.
  def hours_payments
    members = OrganizationStaffMember.where(person_id: person.id)
                                     .includes(staff_role_qualifications: :house_role).index_by(&:organization_id)
    StaffTimeEntry.where(person_id: person.id).where.not(offline_paid_at: nil)
                  .includes(:organization, :house_role, shift_assignment: { shift: :house_role }).map do |e|
      member = members[e.organization_id]
      cents = e.offline_total_cents || (member ? member.amount_cents_for(e.effective_house_role, hours: e.hours) : 0)
      label = e.offline_reimbursement_only? ? "Reimbursement" : hours_label(e)
      Payment.new(kind: "hours", id: e.id, org: e.organization&.name, paid_at: e.offline_paid_at, method: nil,
                  cents: cents, offset_cents: nil,
                  lines: [ Line.new(label: label, detail: [ e.started_at&.strftime("%B %-d, %Y"), e.offline_payment_note.presence ].compact.join(" · "),
                                    cents: cents) ])
    end
  end

  # A share that went wholly toward what they owed: nothing deposited.
  def offset_payments
    ContractPayment.joins(contract: :contractor).where(contractors: { person_id: person.id })
                   .direction_outgoing.status_paid.where(payment_method: "offset")
                   .includes(contract: :organization).map do |share|
      cents = (share.amount.to_d * 100).round
      label = "#{share.contract.production_name.presence || share.contract.contractor_name} — #{self.class.payee_words(share.display_name)}"
      paid_down = self.class.offset_paid_down(share).map { |c| Line.new(label: c.display_name, cents: -(c.amount.to_d * 100).round) }
      paid_down = [ Line.new(label: "Went toward what you owe", cents: -cents) ] if paid_down.empty?
      Payment.new(kind: "offset", id: share.id, org: share.contract.organization&.name, paid_at: share.paid_date,
                  method: "offset", cents: 0, offset_cents: cents,
                  lines: [ Line.new(label: label, cents: cents, deductions: paid_down) ])
    end
  end

  # The charges a share settled by offset paid down: settled by deduction on
  # the same run (the share's reference names it).
  def self.offset_paid_down(share)
    run_id = share.reference_number.to_s[/run #(\d+)/, 1]
    return [] unless run_id

    share.contract.contract_payments.direction_incoming.status_paid
         .where(payment_method: "payout_deduction", reference_number: "offset_run_#{run_id}").order(:due_date, :id).to_a
  end

  def dates_text(range)
    return nil if range.blank?

    min, max = range.map(&:to_date)
    min == max ? min.strftime("%B %-d, %Y") : "#{min.strftime('%b %-d')} – #{max.strftime('%b %-d, %Y')}"
  end
end
