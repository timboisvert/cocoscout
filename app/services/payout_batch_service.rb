# frozen_string_literal: true

# Builds and runs payout batches. Building gathers every payee with a positive
# balance who can receive Stripe payouts; running transfers each item to its
# connected account and posts the debiting ledger entries.
#
# Funding (org -> platform) is assumed handled before #process! (the batch's
# funding_status/PaymentIntent hooks are where an ACH/card debit would live).
class PayoutBatchService
  # Payee types that can hold a Stripe Connect account (groups/guests can't).
  PAYABLE_TYPES = %w[Person Contractor].freeze

  # Batch statuses that still "hold" money: an open draft (fund it from its own
  # run), a run mid-flight, or a funded run partially paid (some payees still
  # waiting on a bank — their slice stays committed to the run). Money committed
  # to one of these has posted its earning to the ledger but not yet its
  # offsetting payout, so a balance sweep must NOT grab it again.
  UNSETTLED_BATCH_STATUSES = %w[draft funding funded processing partially_paid].freeze

  # Create a draft batch with one item per eligible payee. The amount is the
  # payee's ledger balance MINUS anything already committed to another open/
  # in-flight run — so this balance sweep never double-pays money that's already
  # sitting in an open staff_pay/performer draft. Returns the batch (no items if
  # nobody has an un-committed positive balance).
  def self.build_for(organization:, created_by: nil, trigger: "manual")
    batch = PayoutBatch.create!(organization: organization, created_by: created_by, trigger: trigger, status: "draft")
    committed = committed_by_payee(organization, except_batch: batch)

    organization.payout_balances_by_payee.each do |(payee_type, payee_id), cents|
      next unless PAYABLE_TYPES.include?(payee_type)

      available = cents - committed[[ payee_type, payee_id ]].to_i
      next unless available.positive?

      payee = payee_type.constantize.find_by(id: payee_id)
      next unless payee&.can_receive_payouts?

      batch.items.create!(payee: payee, amount_cents: available)
    end

    batch.recalculate_total!
    batch
  end

  # Cents each payee already has staged in an open/in-flight run (pending items
  # only — a paid item already posted its payout to the ledger). Keyed by
  # [payee_type, payee_id] to match payout_balances_by_payee.
  def self.committed_by_payee(organization, except_batch: nil)
    scope = PayoutBatchItem
      .joins(:payout_batch)
      .where(payout_batches: { organization_id: organization.id, status: UNSETTLED_BATCH_STATUSES })
      .where(status: "pending")
    scope = scope.where.not(payout_batch_id: except_batch.id) if except_batch&.persisted?
    scope.group(:payee_type, :payee_id).sum(:amount_cents)
  end

  # Undo an unfunded draft run. Returns tied staff hours to the approved-unpaid
  # pool (dependent: :nullify clears payout_batch_id on destroy, but not paid_at),
  # then destroys the batch — cascading to its items, contributions, and the
  # earning ledger entries those posted. Draft-only: never touch money in flight.
  #
  # For a staff run, everything hand-entered (tips + their per-day worksheets,
  # bonuses, reimbursements, ad-hoc hours, included time entries) is first
  # written back into the org's shared Pay People draft — a tips number read
  # off the bar's POS exists nowhere else, so a discard must never eat it.
  def self.discard!(batch)
    raise Error, "Only a draft run can be discarded." unless batch.status == "draft"

    ActiveRecord::Base.transaction do
      rebuild_staff_pay_draft!(batch) if batch.kind == "staff_pay"
      batch.staff_time_entries.update_all(paid_at: nil, updated_at: Time.current)
      batch.destroy!
    end
    batch
  end

  # Reconstruct the Pay People draft blob (the same shape the grid's autosave
  # writes — see pay_draft_controller.js #serialize) from a draft staff run's
  # items and contributions, and store it as the org's shared draft. Multiple
  # add-to-run visits merge: amounts sum, worksheets and ad-hoc lines concatenate.
  def self.rebuild_staff_pay_draft!(batch)
    org = batch.organization
    members_by_person = org.organization_staff_members.index_by(&:person_id)
    entries_by_person = batch.staff_time_entries.group_by(&:person_id)

    dollars = ->(cents) { format("%.2f", cents / 100.0) }
    sheet = ->(worksheet_entries) { worksheet_entries.map { |w| "#{w['date']}|#{dollars.call(w['amount_cents'].to_i)}" } }

    lines = {}
    batch.items.includes(:payee, :payout_contributions).each do |item|
      next unless item.payee.is_a?(Person)

      member = members_by_person[item.payee_id]
      next unless member

      line = Hash.new { |h, k| h[k] = 0 }
      arrays = Hash.new { |h, k| h[k] = [] }
      item.payout_contributions.each do |c|
        case c.label
        when /\AWorked hours/
          arrays["adhoc"].concat(Array(c.details&.dig("adhoc")))
        when "Bonus" then line["bonus"] += c.amount_cents
        when "Reimbursement" then line["reimbursement"] += c.amount_cents
        when "Tips"
          line["tips"] += c.amount_cents
          arrays["tips_sheet"].concat(sheet.call(c.worksheet_entries))
        when "Cash tips (recorded)"
          line["cash_tips"] += c.amount_cents
          arrays["cash_tips_sheet"].concat(sheet.call(c.worksheet_entries))
        end
      end

      draft_line = line.transform_values { |cents| dollars.call(cents) }
      arrays.each { |k, v| draft_line[k] = v if v.any? }
      entry_ids = entries_by_person[item.payee_id]&.map { |e| e.id.to_s }
      draft_line["time_entry_ids"] = entry_ids if entry_ids&.any?

      lines[member.id.to_s] = draft_line if draft_line.any?
    end
    return if lines.empty?

    PayDraft.write(org, JSON.generate({ "funding_method" => "ach", "lines" => lines }))
  end

  FUNDING_METHODS = %w[ach card].freeze

  # Fund the batch from the org: an ACH debit (default, cheap, settles in a few
  # days) or a card charge (instant "pay now" rush). Creates a PaymentIntent
  # against the org's Stripe customer; card funding that succeeds immediately is
  # advanced straight into processing, while ACH waits for the webhook.
  def self.fund!(batch, method: nil, payment_method_id: nil)
    return batch if batch.total_cents.zero?

    # The payday is "the day we send the money" — it drives the expected-deposit
    # window payees see. A run planned for an earlier day that slipped (created
    # Friday, funded Monday) must not advertise a date in the past, so freshen
    # it at the moment of submission.
    batch.update!(payday: Date.current) if batch.payday.blank? || batch.payday < Date.current

    org = batch.organization
    payment_method = payment_method_id.presence || org.funding_payment_method_id.presence
    raise Error, "Connect a bank or card to fund payouts first." if payment_method.blank?

    # Money released back from earlier funded runs (payees paid another way)
    # never left the Stripe balance — spend it before debiting the bank.
    credit_used = PayoutFundingCredit.consume!(org, batch.total_cents)
    debit_cents = batch.total_cents - credit_used

    if debit_cents <= 0
      # Fully covered by credit: no PaymentIntent at all — the balance already
      # holds the money, so the run advances straight to paying.
      batch.update!(status: "funding", funding_status: "succeeded", funding_payment_intent_id: nil)
      advance_funding!(batch, "succeeded")
      PayoutRunSubmittedNotificationJob.perform_later(batch.id)
      return batch
    end

    # The Stripe payment-method type: prefer the connected source's type, else
    # the caller's ach/card choice.
    pm_type = org.funding_payment_method_type.presence || (method == "card" ? "card" : "us_bank_account")

    intent = Stripe::PaymentIntent.create(
      amount: debit_cents,
      currency: "usd",
      customer: org.stripe_customer_id,
      payment_method: payment_method,
      payment_method_types: [ pm_type ],
      confirm: true,
      off_session: true,
      transfer_group: "org_#{org.id}",
      metadata: { payout_batch_id: batch.id, organization_id: org.id }
    )
    batch.update!(status: "funding", funding_payment_intent_id: intent.id, funding_status: intent.status)
    advance_funding!(batch, intent.status, funded_cents: intent.amount)
    # The run is submitted — tell the org's chosen managers (who's being paid,
    # how much, expected deposit window). Async; no recipients chosen = no-op.
    PayoutRunSubmittedNotificationJob.perform_later(batch.id)
    batch
  rescue Stripe::StripeError => e
    # The debit never happened — give back any credit this attempt consumed so
    # the org's available balance stays truthful.
    if defined?(credit_used) && credit_used.to_i.positive?
      PayoutFundingCredit.create!(organization: batch.organization, amount_cents: credit_used,
                                  note: "Restored after failed funding of run ##{batch.id}")
    end
    batch.update!(status: "failed", funding_status: "failed")
    raise Error, e.message
  end

  # Move a batch forward based on its funding PaymentIntent status. Called from
  # #fund! (instant card) and the payment_intent webhook (ACH settlement).
  # funded_cents is the intent's amount — the org money that actually entered
  # the shared Stripe balance, credited to the org's cash ledger on success.
  # (Runs covered entirely by funding credit pass no intent and post nothing —
  # their money is already in the ledger.)
  def self.advance_funding!(batch, intent_status, funded_cents: nil)
    case intent_status
    when "succeeded"
      if funded_cents.to_i.positive?
        OrgCashEntry.post!(
          organization: batch.organization,
          entry_type: "funding",
          amount_cents: funded_cents.to_i,
          source: batch,
          description: "Funding for payout run ##{batch.id}"
        )
      end
      batch.update!(status: "funded", funding_status: "succeeded")
      process!(batch)
    when "processing", "requires_action"
      batch.update!(funding_status: intent_status)
    end
    batch
  end

  class Error < StandardError; end

  # Transfer every payable pending item to its connected account. Each success
  # posts a `payout` ledger entry (debiting the balance); failures leave the
  # balance intact. Payees without a connected bank are SKIPPED, not failed —
  # the funding debit covered them, so their money stays attached to this run
  # (status "partially_paid") and goes out via #pay_remaining! once they
  # connect. A run only reads "completed" when every item is actually paid.
  def self.process!(batch)
    batch.update!(status: "processing")

    source_charge, source_remaining = funding_charge_for(batch)

    batch.items.pending.find_each do |item|
      # No connected bank yet: a transfer would just fail. Leave the item
      # pending — their slice of the funded money waits on this run.
      next unless item.payee.respond_to?(:can_receive_payouts?) && item.payee.can_receive_payouts?

      params = {
        amount: item.amount_cents,
        currency: "usd",
        destination: item.payee.stripe_account_id,
        transfer_group: "org_#{batch.organization_id}",
        metadata: { payout_batch_item_id: item.id, organization_id: batch.organization_id }
      }
      # Draw on the funding charge itself, not the platform's available balance
      # (see funding_charge_for). Falls back to the balance when the charge's
      # transferable capacity can't cover this item (credit-funded slices).
      use_source = source_charge.present? && item.amount_cents <= source_remaining
      params[:source_transaction] = source_charge if use_source

      # Reserve the money on the org's cash ledger before touching Stripe.
      # Charge-pinned transfers can't be blocked (Stripe guarantees the charge
      # covers them — enforce: false); a fallback draw on the shared platform
      # balance must fit within the org's own held money, or it parks here
      # instead of spending another org's cash.
      begin
        OrgCashEntry.debit!(
          organization: batch.organization,
          amount_cents: item.amount_cents,
          source: item,
          enforce: !use_source,
          description: "Payout run ##{batch.id} transfer"
        )
      rescue OrgCashEntry::InsufficientFunds
        item.mark_failed!("Insufficient held balance — not sent")
        next
      end

      # The idempotency key survives a crash between the transfer succeeding
      # and mark_paid! landing: the item is still pending with the same
      # updated_at, so the retry replays the same transfer instead of paying
      # twice. Any status change (mark_failed!, the pending reset in
      # pay_remaining!) touches updated_at and mints a fresh key.
      transfer = Stripe::Transfer.create(
        params,
        idempotency_key: "payout-batch-item-#{item.id}-#{item.updated_at.to_i}"
      )
      source_remaining -= item.amount_cents if use_source
      item.mark_paid!(transfer_id: transfer.id)
      settle_item_sources!(item, transfer.id)
      record_performer_activation!(batch, item)
    rescue Stripe::StripeError => e
      item.mark_failed!(e.message)
    end

    finalize_status!(batch)

    # Tell each payee now, not at submission. process! only ever runs once
    # funding has actually succeeded (advance_funding! calls it solely on
    # "succeeded"; pay_remaining! requires it), so by here the money is real:
    # an ACH debit that was still settling — or that bounced — has never
    # promised anyone a deposit. It also means the expected-deposit window is
    # counted from the day the transfer happened rather than from submit day,
    # which on ACH can be several days earlier.
    PayoutSentPayeeNotificationJob.perform_later(batch.id)
    batch
  end

  # The Stripe charge that funded this run, plus how much of it is still
  # transferable: [charge_id, remaining_cents].
  #
  # Transfers created with source_transaction draw on that specific charge
  # rather than the platform's available balance, which closes two races that
  # each failed a whole run in Aug 2026: an ACH debit that has settled but
  # whose funds haven't become "available" yet, and an automatic platform
  # payout sweeping the balance to our own bank before the transfers ran.
  # Either way the plain transfers bounced with "insufficient funds" even
  # though the org's money was fully collected.
  #
  # Remaining capacity conservatively assumes every already-paid item drew on
  # this charge, so a retry can never over-commit it; items it can't cover
  # (e.g. the credit-funded slice of a run) fall back to the plain balance.
  # Best-effort: if Stripe can't tell us, transfers proceed the old way.
  def self.funding_charge_for(batch)
    return [ nil, 0 ] if batch.funding_payment_intent_id.blank?

    intent = Stripe::PaymentIntent.retrieve(batch.funding_payment_intent_id)
    charge = intent.latest_charge
    charge_id = charge.is_a?(String) ? charge : charge&.id
    return [ nil, 0 ] if charge_id.blank?

    [ charge_id, intent.amount - batch.items.paid.sum(:amount_cents) ]
  rescue Stripe::StripeError => e
    Rails.logger.warn("[PayoutBatchService] no funding charge for batch #{batch.id}: #{e.message}")
    [ nil, 0 ]
  end

  # A funded run stays open until every person in it is paid: all paid →
  # completed (and only then stamped completed_at); anything still pending or
  # failed → partially_paid, waiting for #pay_remaining!.
  def self.finalize_status!(batch)
    if batch.items.where.not(status: "paid").none?
      batch.update!(status: "completed", completed_at: Time.current)
    else
      batch.update!(status: "partially_paid", completed_at: nil)
    end
  end

  # Pay whoever in this already-funded run has become payable since the last
  # pass (connected a bank, or a transient transfer failure). No new funding —
  # the original debit already covered the full run; these transfers draw on
  # that money. Failed items get one more chance each call.
  def self.pay_remaining!(batch)
    unless batch.funding_status == "succeeded" || batch.skips_funding?
      raise Error, "This run hasn't been funded yet — fund it first."
    end
    unless %w[partially_paid processing failed].include?(batch.status)
      raise Error, "This run has nothing left to pay."
    end

    batch.items.where(status: "failed").update_all(status: "pending", error: nil, updated_at: Time.current)
    process!(batch)
  end

  # Mark a paid performer a billable "active performer" for the payout's month —
  # this is the month Stripe bills us the active-account fee, so our $3 charge
  # lands in the same month. Only performer runs paying an individual Person;
  # staff are billed separately (StaffActivation, on scheduling). Best-effort:
  # a billing hiccup must never fail an already-completed payout.
  def self.record_performer_activation!(batch, item)
    return unless batch.kind == "performer" && item.payee.is_a?(Person)

    # Don't count a person paid *only* as a contractor (contract payments ride the
    # performer run too) toward the $3/active-performer charge — that's for
    # performing. A person with any show-payout contribution still counts.
    contributions = item.payout_contributions.to_a
    return if contributions.any? && contributions.all? { |c| c.source_type == "ContractPayment" }

    PerformerActivation.record!(
      organization: batch.organization, person: item.payee, month: item.paid_at || Time.current
    )
  rescue StandardError => e
    Rails.logger.warn("Performer activation failed for payout item #{item.id}: #{e.message}")
  end

  # Flip each of a paid item's contribution sources to "paid" for traceability
  # (e.g. mark the ShowPayoutLineItems paid so the show reflects it). The item
  # itself already posted the ledger payout, so sources don't touch the ledger.
  def self.settle_item_sources!(item, transfer_id)
    item.payout_contributions.includes(:source).each do |contribution|
      source = contribution.source
      source.mark_paid_via_payout_run!(reference_id: transfer_id) if source.respond_to?(:mark_paid_via_payout_run!)
    end
  end

  # The inverse, for money that came back. Without it a returned payout leaves
  # every show payout, advance and contract payment still reading "paid" — the
  # org would have no idea it still owes the money.
  def self.unsettle_item_sources!(item)
    item.payout_contributions.includes(:source).each do |contribution|
      source = contribution.source
      source.mark_unpaid_via_payout_run! if source.respond_to?(:mark_unpaid_via_payout_run!)
    end
  end

  # A paid item whose money the bank sent back: reverse the ledger, put the
  # sources back to owed, and recompute the run's status so a "completed" run
  # doesn't quietly contain a returned item.
  #
  # cash_returned: true only when the money actually re-entered OUR platform
  # balance (a transfer reversal). A bank return leaves it in the payee's
  # Connect balance, so the org's cash ledger must NOT be credited for it.
  def self.return_item!(item, reason:, cash_returned: false)
    item.mark_returned!(reason: reason)
    if cash_returned
      OrgCashEntry.post!(
        organization: item.organization,
        entry_type: "transfer_reversal",
        amount_cents: item.amount_cents,
        source: item,
        description: "Transfer reversed on payout run ##{item.payout_batch_id}"
      )
    end
    unsettle_item_sources!(item)
    finalize_status!(item.payout_batch)
    PayoutReturnedNotificationJob.perform_later(item.id)
    item
  end
end
