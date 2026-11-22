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

  # "Everyone owed": top up the org's ONE open run with each payee's balance
  # that isn't on a run yet, per kind of money. For every payee and category
  # the available amount is their ledger balance MINUS what another open or
  # in-flight run already holds MINUS what this run already carries — so the
  # sweep never double-pays money that's already staged. Each positive amount
  # becomes a "Balance payout" line of that category on the payee's item.
  # Nothing is funded here: the manager reviews the run and funds it.
  # Returns the open run (possibly with nothing new on it).
  def self.build_for(organization:, created_by: nil, trigger: "manual")
    batch = PayoutBatch.open_for(organization, created_by: created_by, trigger: trigger)
    elsewhere = committed_by_payee_and_category(organization, except_batch: batch)
    here = committed_by_payee_and_category(organization, only_batch: batch)

    ActiveRecord::Base.transaction do
      organization.payout_ledger_entries
                  .group(:payee_type, :payee_id, :category).sum(:amount_cents)
                  .each do |(payee_type, payee_id, category), cents|
        next unless PAYABLE_TYPES.include?(payee_type)

        key = [ payee_type, payee_id, category ]
        available = cents - elsewhere[key].to_i - here[key].to_i
        next unless available.positive?

        payee = payee_type.constantize.find_by(id: payee_id)
        next unless payee&.can_receive_payouts?

        item = batch.items.find_by(payee: payee) || batch.items.create!(payee: payee, amount_cents: available)
        batch.payout_contributions.create!(payout_batch_item: item, payee: payee, amount_cents: available,
                                           category: category, label: "Balance payout")
        item.settle_amount!
      end
      batch.recalculate_total!
    end
    batch
  end

  # Cents each payee's pending items hold, per kind of money, across runs that
  # still hold money (open drafts and runs in flight):
  # { [payee_type, payee_id, category] => cents }. Uses each item's
  # category_split, so it's what the item will actually debit per ledger.
  def self.committed_by_payee_and_category(organization, except_batch: nil, only_batch: nil)
    scope = PayoutBatchItem
      .joins(:payout_batch)
      .where(payout_batches: { organization_id: organization.id, status: UNSETTLED_BATCH_STATUSES })
      .where(status: "pending")
    scope = scope.where.not(payout_batch_id: except_batch.id) if except_batch&.persisted?
    scope = scope.where(payout_batch_id: only_batch.id) if only_batch
    scope.includes(:payout_contributions).each_with_object(Hash.new(0)) do |item, out|
      item.category_split.each { |category, cents| out[[ item.payee_type, item.payee_id, category ]] += cents }
    end
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
  # Any staff pay on it — everything hand-entered (tips + their per-day
  # worksheets, bonuses, reimbursements, ad-hoc hours, included time entries)
  # — is first written back into the org's shared Pay People draft: a tips
  # number read off the bar's POS exists nowhere else, so a discard must never
  # eat it. Performer lines simply come off and can be added again.
  def self.discard!(batch)
    raise Error, "Only a draft run can be discarded." unless batch.status == "draft"

    ActiveRecord::Base.transaction do
      rebuild_staff_pay_draft!(batch)
      batch.staff_time_entries.update_all(paid_at: nil, updated_at: Time.current)
      batch.destroy!
    end
    batch
  end

  # Reconstruct the Pay People draft blob (the same shape the grid's autosave
  # writes — see pay_draft_controller.js #serialize) from a draft run's staff
  # lines, and store it as the org's shared draft. Multiple add-to-run visits
  # merge: amounts sum, worksheets and ad-hoc lines concatenate. Only
  # "staffing" lines count — a performer line that happens to be labeled
  # "Bonus" is not staff pay. No staff lines, nothing written.
  def self.rebuild_staff_pay_draft!(batch)
    org = batch.organization
    members_by_person = org.organization_staff_members.index_by(&:person_id)
    entries_by_person = batch.staff_time_entries.group_by(&:person_id)

    lines = {}
    batch.items.includes(:payee, :payout_contributions).each do |item|
      member, draft_line = staff_draft_line(item, members_by_person, entries_by_person)
      lines[member.id.to_s] = draft_line if draft_line.present?
    end
    return if lines.empty?

    PayDraft.write(org, JSON.generate({ "funding_method" => "ach", "lines" => lines }))
  end

  # One person's staff pay taken out of a draft run goes back into the Pay
  # People draft, added to whatever that draft already holds for them, and
  # nobody else's line is touched (PayoutRunRemoval).
  def self.return_staff_pay_to_draft!(batch, item)
    org = batch.organization
    member, draft_line = staff_draft_line(item, org.organization_staff_members.index_by(&:person_id),
                                          batch.staff_time_entries.group_by(&:person_id))
    return if draft_line.blank?

    blob = (JSON.parse(PayDraft.read(org).presence || "{}") rescue {})
    blob["funding_method"] ||= "ach"
    lines = (blob["lines"] ||= {})
    existing = lines[member.id.to_s] || {}
    lines[member.id.to_s] = existing.merge(draft_line) do |_key, old, new|
      if old.is_a?(Array) || new.is_a?(Array) then (Array(old) + Array(new)).uniq
      else format("%.2f", old.to_f + new.to_f)
      end
    end
    PayDraft.write(org, JSON.generate(blob))
  end

  # [member, line] for one item: its staff lines in the Pay People draft's
  # shape. Only "staffing" lines count — a performer line that happens to be
  # labeled "Bonus" is not staff pay. No member or no staff lines: no line.
  def self.staff_draft_line(item, members_by_person, entries_by_person)
    return [ nil, nil ] unless item.payee.is_a?(Person)

    member = members_by_person[item.payee_id]
    return [ nil, nil ] unless member

    dollars = ->(cents) { format("%.2f", cents / 100.0) }
    sheet = ->(worksheet_entries) { worksheet_entries.map { |w| "#{w['date']}|#{dollars.call(w['amount_cents'].to_i)}" } }
    line = Hash.new { |h, k| h[k] = 0 }
    arrays = Hash.new { |h, k| h[k] = [] }
    item.payout_contributions.select { |c| c.category == "staffing" }.each do |c|
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
    [ member, draft_line.presence ]
  end

  FUNDING_METHODS = %w[ach card].freeze
  IN_PROGRESS_STATUSES = %w[funding funded processing partially_paid completed].freeze

  # Fund the batch from the org: an ACH debit (default, cheap, settles in a few
  # days) or a card charge (instant "pay now" rush). Creates a PaymentIntent
  # against the org's Stripe customer; card funding that succeeds immediately is
  # advanced straight into processing, while ACH waits for the webhook.
  #
  # An organization with a CocoScout balance pays from it first (Tim,
  # 2026-11-22): see start_from_balance!. Everyone else funds the whole run
  # from the bank, as before.
  def self.fund!(batch, method: nil, payment_method_id: nil)
    return batch if batch.total_cents.zero?

    # One funding at a time per run: a double-click, or two tabs, must never
    # debit the bank twice. The attempt number keys Stripe's idempotency, so
    # a network retry of this same attempt returns the same PaymentIntent.
    attempt = batch.with_lock do
      raise Error, "This run is already being paid." if IN_PROGRESS_STATUSES.include?(batch.status)

      batch.increment!(:funding_attempts)
      # A fresh attempt starts clean: the last failure's reason is history.
      batch.update!(funding_error: nil) if batch.funding_error.present?
      batch.funding_attempts
    end

    # The payday is "the day we send the money" — it drives the expected-deposit
    # window payees see. A run planned for an earlier day that slipped (created
    # Friday, funded Monday) must not advertise a date in the past, so freshen
    # it at the moment of submission.
    batch.update!(payday: Date.current) if batch.payday.blank? || batch.payday < Date.current

    return start_from_balance!(batch, attempt: attempt, payment_method_id: payment_method_id) if balance_first?(batch)

    fund_rest!(batch, attempt: attempt, payment_method_id: payment_method_id, notify: true)
  end

  # Runs that pay from the organization's CocoScout balance before its bank.
  def self.balance_first?(batch)
    !batch.skips_funding? && CocoScoutBalance.pooled?(batch.organization)
  end

  # Balance first (Tim, 2026-11-22): the run pays everyone the balance covers
  # right away, in pay order (PayoutPayOrder), one whole payment each. The rest
  # wait on the run ("awaiting_balance"): every morning PayoutBalanceWavesJob
  # pays whoever the balance now covers, and once it covers everyone left, or
  # on the run's bank_due_at (bank_due_at_for: the organization's days after
  # submit, or at once), fund_rest! funds what's left, from the balance and the bank,
  # and the run carries on exactly as a funded run always has.
  def self.start_from_balance!(batch, attempt:, payment_method_id: nil)
    # The bank pays whatever the balance can't, sooner or later: a run the
    # balance can't cover today needs a bank behind it before it starts.
    if (payment_method_id.presence || batch.organization.funding_payment_method_id).blank? && rest_bank_cents(batch).positive?
      message = "Connect a bank or card to fund payouts first."
      batch.update!(funding_error: message)
      raise Error, message
    end

    batch.update!(status: "funding", funding_status: "awaiting_balance", funding_started_at: Time.current,
                  funding_payment_intent_id: nil, bank_due_at: bank_due_at_for(batch.organization))
    begin
      advance_from_balance!(batch, attempt: attempt, payment_method_id: payment_method_id)
    rescue Error
      # The bank half didn't start (no bank connected, or the debit was
      # refused). Whoever the balance paid stays paid; the reason is on the
      # run, and the rest wait for the balance or the next try. When the
      # balance paid nobody, nothing happened: the run is a draft again and
      # the manager sees why.
      raise if batch.reload.items.where(paid_from_balance: true).none? && back_to_draft!(batch)
    end
    batch.reload
    if batch.funding_status == "succeeded" && batch.items.where(paid_from_balance: true).none?
      PayoutRunSubmittedNotificationJob.perform_later(batch.id, funded: true)
    elsif batch.funding_status == "awaiting_balance" || batch.items.where(paid_from_balance: true).exists?
      PayoutRunSubmittedNotificationJob.perform_later(batch.id, from_balance: true)
    else
      PayoutRunSubmittedNotificationJob.perform_later(batch.id, funded: false)
    end
    batch
  end

  # A balance-first run that paid nobody and couldn't start its bank debit.
  # False when another draft opened meanwhile (one open run per organization):
  # it stays waiting on the balance, the reason on it.
  def self.back_to_draft!(batch)
    batch.update!(status: "draft", funding_status: nil, funding_started_at: nil, bank_due_at: nil, funding_payment_intent_id: nil)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # When the bank pays whoever the balance hasn't: the morning of the day the
  # organization's days from now (PayoutBalanceWavesJob runs each morning), or
  # now when the organization doesn't wait on the balance, or no money is on
  # its way into it (nothing settling, nothing sold for shows still to come),
  # since waiting would only delay everyone.
  def self.bank_due_at_for(organization, now: Time.current)
    days = organization.payout_bank_after_days.to_i.clamp(0, 30)
    return now if days.zero? || !organization.payout_waits_on_balance

    summary = CocoScoutBalance.summary(organization)
    return now unless (summary.settling_cents + summary.upcoming_cents).positive?

    zone = ActiveSupport::TimeZone[organization.time_zone] || Time.zone
    (now.in_time_zone(zone).to_date + days).in_time_zone(zone)
  end

  # Pay whoever the balance now covers; then, when the balance covers everyone
  # left, or its scheduled bank debit has come (or bank: true, a manager's "Pay the rest
  # from my bank"), fund the rest. A run whose bank half failed waits for a
  # manager before the bank is tried again. notify: the morning pass tells the
  # managers when it paid more (PayoutRunMorePaidNotificationJob); a run it
  # finished gets the usual "everyone's paid" instead.
  def self.advance_from_balance!(batch, bank: false, attempt: nil, payment_method_id: nil, notify: false)
    return batch unless batch.status == "funding" && batch.funding_status == "awaiting_balance"

    paid_ids = pay_from_balance!(batch)
    batch.reload
    if rest_cents(batch).zero?
      batch.update!(status: "funded", funding_status: "succeeded", funded_at: Time.current)
      finalize_status!(batch)
      return batch
    end

    begin
      due = batch.bank_due_at.present? && batch.bank_due_at <= Time.current && batch.funding_error.blank?
      if bank || due || rest_bank_cents(batch).zero?
        attempt ||= batch.with_lock do
          batch.increment!(:funding_attempts)
          batch.funding_attempts
        end
        batch.update!(funding_error: nil) if bank && batch.funding_error.present?
        fund_rest!(batch, attempt: attempt, payment_method_id: payment_method_id)
      end
    ensure
      if notify && paid_ids.any? && !batch.reload.completed?
        PayoutRunMorePaidNotificationJob.perform_later(batch.id, paid_ids)
      end
    end
    batch
  end

  # Everyone on the run not paid yet: what funding the rest has to cover (the
  # run's total, for a run nobody on it has been paid from yet).
  def self.rest_cents(batch)
    [ batch.total_cents.to_i - batch.items.where(status: %w[paid returned]).sum(:amount_cents), 0 ].max
  end

  # What the bank would be debited for the rest today, after held money,
  # funding credit and the balance.
  def self.rest_bank_cents(batch)
    org = batch.organization
    fundable = [ rest_cents(batch) - batch.held_cents, 0 ].max
    fundable -= [ PayoutFundingCredit.available_cents(org), fundable ].min
    [ fundable - CocoScoutBalance.available_cents(org), 0 ].max
  end

  # One pass of the balance over the run: each person it covers, in pay order,
  # paid in full now. Someone who doesn't fit is passed over for the next, so
  # the money pays as many people as it can. Nobody is paid in parts, and
  # nobody without a connected bank takes any of it (they wait, as they always
  # have). Returns the ids of the items it paid.
  def self.pay_from_balance!(batch)
    conn = ActiveRecord::Base.connection
    return [] unless conn.select_value("SELECT pg_try_advisory_lock(3085, #{batch.id.to_i})")

    begin
      waiting = batch.items.pending.where("amount_cents > 0").includes(:payee, :payout_contributions).select(&:payable_now?)
      budget = CocoScoutBalance.available_cents(batch.organization)
      paid = []
      PayoutPayOrder.sort(batch, waiting).each do |item|
        break unless budget.positive?
        next if item.amount_cents > budget
        next unless send_from_balance!(batch, item)

        budget -= item.amount_cents
        paid << item.id
      end
      PayoutSentPayeeNotificationJob.perform_later(batch.id) if paid.any?
      paid
    ensure
      conn.select_value("SELECT pg_advisory_unlock(3085, #{batch.id.to_i})")
    end
  end

  # Who the balance would pay right now, without paying anyone: the run
  # page's words before a manager presses Pay now. { now:, later:, no_bank: },
  # each a list of pending items (now and later in pay order).
  def self.balance_preview(batch, items = batch.items.includes(:payee, :payout_contributions).to_a)
    pending = items.select { |item| item.status == "pending" && item.amount_cents.to_i.positive? }
    payable, no_bank = pending.partition(&:payable_now?)
    budget = CocoScoutBalance.available_cents(batch.organization)
    now = []
    PayoutPayOrder.sort(batch, payable).each do |item|
      next if item.amount_cents > budget

      now << item
      budget -= item.amount_cents
    end
    { now: now, later: PayoutPayOrder.sort(batch, payable - now), no_bank: no_bank }
  end

  def self.send_from_balance!(batch, item)
    if item.partner_organization?
      pay_into_balance!(batch, item, from_balance: true)
    else
      send_transfer!(batch, item, transfer_group: "org_#{batch.organization_id}", from_balance: true)
    end
    item.reload
    return false unless item.paid?

    item.update_columns(paid_from_balance: true)
    true
  end

  # Fund whoever on the run isn't paid yet: held money (course sales and
  # collected contract money already in CocoScout), then funding credit, then
  # the CocoScout balance, and the bank for the rest. For a run that wasn't
  # balance first this is the whole run. notify: tell the managers it was
  # submitted (the first funding of a run that wasn't balance first).
  def self.fund_rest!(batch, attempt:, payment_method_id: nil, notify: false)
    org = batch.organization
    payment_method = payment_method_id.presence || org.funding_payment_method_id.presence
    # A balance-first run whose bank half fails goes back to waiting on the
    # balance, never to "failed": some of its people are already paid.
    resumable = batch.funding_status == "awaiting_balance"

    # Money CocoScout already holds for the org — course sales and collected
    # contract payments staged on this run — never needs to come out of their
    # bank; ACH-debiting the org to hand them their own held money would charge
    # them twice. Only the remainder is fundable.
    held_cents = batch.held_cents
    fundable_cents = [ rest_cents(batch) - held_cents, 0 ].max

    # Money released back from earlier funded runs (payees paid another way)
    # never left the Stripe balance — spend it before debiting the bank.
    credit_used = PayoutFundingCredit.consume!(org, fundable_cents)
    batch.update!(credit_applied_cents: credit_used)
    debit_cents = fundable_cents - credit_used

    # The theater's CocoScout balance — ticket money from shows that have
    # happened — pays next, so the run goes out today instead of waiting on
    # an ACH debit. Claimed under the org's cash lock so two runs can't spend
    # the same dollars. An org with no ticket money has nothing to claim.
    balance_used = claim_balance!(batch, debit_cents)
    debit_cents -= balance_used

    if debit_cents <= 0
      # Nothing to debit (held money and/or credit covers the run): no
      # PaymentIntent at all — the balance already holds the money, so the run
      # advances straight to paying.
      batch.update!(status: "funding", funding_status: "succeeded", funding_payment_intent_id: nil)
      advance_funding!(batch, "succeeded", at_submit: true)
      # Funded in this same request: the submitted notice says so, and no
      # separate funded notice follows.
      PayoutRunSubmittedNotificationJob.perform_later(batch.id, funded: true) if notify
      return batch
    end

    if payment_method.blank?
      # Nothing was debited — hand back the credit and balance this attempt
      # claimed so the org's available balance stays truthful.
      message = "Connect a bank or card to fund payouts first."
      batch.update!(balance_applied_cents: 0, credit_applied_cents: 0, funding_error: message)
      if credit_used.positive?
        PayoutFundingCredit.create!(organization: org, amount_cents: credit_used,
                                    note: "Restored after failed funding of run ##{batch.id}")
      end
      raise Error, message
    end

    # No payment_method_types: Stripe rejects that parameter on this account
    # since Oct 2026 (payment methods are managed from the Dashboard). The
    # ACH configuration allows the bank debit the Default one keeps off.
    intent = Stripe::PaymentIntent.create({
      amount: debit_cents,
      currency: "usd",
      customer: org.stripe_customer_id,
      payment_method: payment_method,
      **PayoutFundingService.ach_configuration_params,
      confirm: true,
      off_session: true,
      transfer_group: "org_#{org.id}",
      metadata: { payout_batch_id: batch.id, organization_id: org.id }
    }, { idempotency_key: "payout-run-funding-#{batch.id}-#{attempt}" })
    batch.update!(status: "funding", funding_payment_intent_id: intent.id, funding_status: intent.status, funding_started_at: Time.current)
    advance_funding!(batch, intent.status, funded_cents: intent.amount, at_submit: true)
    # The run is submitted — tell the org's chosen managers (who's being paid,
    # how much, expected deposit window). Async; no recipients chosen = no-op.
    # A card settles here and now, so the words say "submitted and funded";
    # an ACH debit gets its own funded notice when the webhook lands.
    PayoutRunSubmittedNotificationJob.perform_later(batch.id, funded: batch.funded_at.present?) if notify
    batch
  rescue Stripe::StripeError => e
    # The debit never happened — give back any credit this attempt consumed so
    # the org's available balance stays truthful. (A failed run's balance
    # claim stops counting on its own; zeroing it keeps the record plain.)
    if defined?(credit_used) && credit_used.to_i.positive?
      PayoutFundingCredit.create!(organization: batch.organization, amount_cents: credit_used,
                                  note: "Restored after failed funding of run ##{batch.id}")
    end
    # Keep Stripe's own words on the run: a flash message is gone by the time
    # anyone asks why run 29 failed (2026-10-13).
    if resumable
      batch.update!(status: "funding", funding_status: "awaiting_balance", balance_applied_cents: 0, credit_applied_cents: 0,
                    funding_payment_intent_id: nil, funding_error: e.message)
    else
      batch.update!(status: "failed", funding_status: "failed", balance_applied_cents: 0, credit_applied_cents: 0,
                    funding_error: e.message)
    end
    raise Error, e.message
  end

  # The bank debit bounced days later (the ACH webhook). Give back the funding
  # credit the run spent and let go of the balance it claimed, exactly as a
  # failure at submission does, so the org's available money stays truthful.
  # `reason` is Stripe's last_payment_error message when the webhook carries one.
  #
  # A run that paid from the balance first goes back to waiting on it: the
  # people it paid stay paid, and the balance keeps paying the rest until a
  # manager tries the bank again (PayoutFundingFailedNotificationJob tells them).
  def self.funding_failed!(batch, reason: nil)
    batch.with_lock do
      return batch if batch.status == "failed" || batch.funding_status == "awaiting_balance"

      if batch.credit_applied_cents.positive?
        PayoutFundingCredit.create!(organization: batch.organization, amount_cents: batch.credit_applied_cents,
                                    note: "Restored after failed funding of run ##{batch.id}")
      end
      message = reason.presence || "The bank debit was returned by the bank."
      if batch.items.where(paid_from_balance: true).exists?
        batch.update!(status: "funding", funding_status: "awaiting_balance", balance_applied_cents: 0, credit_applied_cents: 0,
                      funding_error: message)
      else
        batch.update!(status: "failed", funding_status: "failed", balance_applied_cents: 0, credit_applied_cents: 0,
                      funding_error: message)
      end
    end
    batch
  end

  # How much of the theater's CocoScout balance (CocoScoutBalance) this run
  # spends instead of debiting the bank — at most what's left to debit.
  # Recorded on the run, which is what takes it out of the balance.
  def self.claim_balance!(batch, debit_cents)
    return 0 unless debit_cents.positive?

    OrgCashEntry.with_org_lock(batch.organization) do
      cents = [ CocoScoutBalance.available_cents(batch.organization), debit_cents ].min
      batch.update!(balance_applied_cents: cents) if cents.positive?
      [ cents, 0 ].max
    end
  end

  # Move a batch forward based on its funding PaymentIntent status. Called from
  # #fund! (instant card) and the payment_intent webhook (ACH settlement).
  # funded_cents is the intent's amount — the org money that actually entered
  # the shared Stripe balance, credited to the org's cash ledger on success.
  # (Runs covered entirely by funding credit pass no intent and post nothing —
  # their money is already in the ledger.)
  #
  # funded_at is stamped the first time the run is funded, and guards the
  # "your run is funded" notice to the organization's chosen people: Stripe
  # repeats webhooks, and a run that's already funded is left alone (its
  # transfers went; pay_remaining! is the retry path). at_submit: funding
  # settled inside fund! itself, so the submitted notice carries the news
  # and no funded notice is sent.
  def self.advance_funding!(batch, intent_status, funded_cents: nil, at_submit: false)
    case intent_status
    when "succeeded"
      return batch if batch.funded_at.present?

      if funded_cents.to_i.positive?
        OrgCashEntry.post!(
          organization: batch.organization,
          entry_type: "funding",
          amount_cents: funded_cents.to_i,
          source: batch,
          description: "Funding for payout run ##{batch.id}"
        )
      end
      batch.update!(status: "funded", funding_status: "succeeded", funded_at: Time.current)
      PayoutRunFundedNotificationJob.perform_later(batch.id) unless at_submit
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
    # Back to paying: the completion notice that follows is a new one (an
    # earlier "partly paid" run that now pays everyone gets "everyone's paid").
    batch.update!(status: "processing", completion_notified_at: nil)

    source_charge, source_remaining, source_group = funding_charge_for(batch)
    transfer_group = "org_#{batch.organization_id}"

    batch.items.pending.find_each do |item|
      # A contract share going into another organization's CocoScout balance
      # never touches a bank: it moves between the two balances.
      if item.partner_organization?
        pay_into_balance!(batch, item)
        next
      end

      # No connected bank yet: a transfer would just fail. Leave the item
      # pending — their slice of the funded money waits on this run.
      next unless item.payable_now?

      # Draw on the funding charge itself, not the platform's available balance
      # (see funding_charge_for). Falls back to the balance when the charge's
      # transferable capacity can't cover this item (credit-funded slices).
      use_source = source_charge.present? && item.amount_cents <= source_remaining
      sent = send_transfer!(batch, item, transfer_group: transfer_group,
                                         source_charge: (source_charge if use_source), source_group: source_group)
      source_remaining -= item.amount_cents if use_source && sent == :paid
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

  # Send one item's transfer to its payee's connected account; returns :paid,
  # :failed, :parked or :short.
  #
  # source_charge: the run's funding charge to draw on (see
  # funding_charge_for), or nil to draw on the platform's balance, which must
  # then fit within the organization's own money. from_balance: a payment
  # from the balance before the run is funded (pay_from_balance!), where
  # anything that stops it leaves the item waiting on the run rather than
  # failed: the bank's funding pays it later if the balance doesn't.
  def self.send_transfer!(batch, item, transfer_group:, source_charge: nil, source_group: nil, from_balance: false)
    params = {
      amount: item.amount_cents,
      currency: "usd",
      destination: item.payee.stripe_account_id,
      transfer_group: transfer_group,
      metadata: { payout_batch_item_id: item.id, organization_id: batch.organization_id }
    }
    if source_charge
      params[:source_transaction] = source_charge
      # A charge-pinned transfer inherits the charge's transfer_group, and
      # Stripe rejects an explicit one that differs ("You cannot use
      # transfer_group if the source_transaction already has one set").
      # Funding charges from before PaymentIntents carried a group can be
      # stamped with something else — inherit rather than fail the payee.
      params.delete(:transfer_group) if source_group.present? && source_group != transfer_group
    end

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
        enforce: source_charge.nil?,
        description: "Payout run ##{batch.id} transfer"
      )
    rescue OrgCashEntry::InsufficientFunds
      return :short if from_balance

      item.mark_failed!("Insufficient held balance — not sent")
      return :failed
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
    item.mark_paid!(transfer_id: transfer.id)
    settle_item_sources!(item, transfer.id)
    :paid
  rescue Stripe::StripeError => e
    if destination_not_ready?(e)
      # Their Stripe account isn't cleared to receive a transfer yet (see
      # StripeConnectService.transferable?). Re-read the account so our copy
      # of "can they be paid" stops claiming yes, and park the item instead
      # of failing it: the money stays on the run, the manager sees "waiting
      # on bank info" rather than a paragraph of Stripe capability jargon,
      # and the account.updated webhook that fires when the capability goes
      # active pays them without anyone clicking.
      resync_payee!(item.payee)
      item.mark_parked!("Stripe hasn't finished clearing their account to receive transfers — we'll send this automatically once it is.")
      :parked
    elsif from_balance
      # Not sent from the balance this time; the run pays them later.
      item.mark_parked!("Not sent from your CocoScout balance yet: #{e.message}")
      :parked
    else
      item.mark_failed!(e.message)
      :failed
    end
  end

  # Pay an item whose payee is another organization (a contractor's own, by
  # the contractor's choice: ContractConnections.pay_target): the money moves
  # from this organization's CocoScout balance into theirs, at once, with no
  # bank transfer and no fee. One transaction: this side's ordinary
  # `transfer` debit, their `partner_payment_in` credit, the item paid and
  # its sources settled all land together or not at all.
  #
  # A funded run's money is already in this organization's ledger, so its
  # items are never blocked; a run paid from the balance must fit within it.
  def self.pay_into_balance!(batch, item, from_balance: false)
    target = item.payee
    unless ContractConnections.balance_available?(target)
      item.mark_failed!("#{target.name} can't be paid into a CocoScout balance any more. Take this out of the run and add it again to pay their bank.")
      return
    end

    payer = batch.organization
    ActiveRecord::Base.transaction do
      OrgCashEntry.debit!(organization: payer, amount_cents: item.amount_cents, source: item,
                          enforce: batch.funding_status != "succeeded",
                          description: "Payout run ##{batch.id}: paid into #{target.name}#{target.name.to_s.end_with?('s') ? "'" : "'s"} CocoScout balance")
      OrgCashEntry.post!(organization: target, entry_type: "partner_payment_in", amount_cents: item.amount_cents, source: item,
                         description: "From #{payer.name}: #{item.payout_contributions.payable.where('amount_cents > 0').pluck(:label).first(2).to_sentence.presence || 'contract payment'}")
      item.mark_paid!
      # It is there the moment the run pays: nothing is on its way to a bank.
      item.update_columns(deposited_at: Time.current)
      settle_item_sources!(item, "balance-org-#{target.id}")
    end
    ContractConnectionNotices.share_paid_into_balance(item)
  rescue OrgCashEntry::InsufficientFunds
    # Paying from the balance before the run is funded: it simply waits.
    item.mark_failed!("Insufficient held balance — not sent") unless from_balance
  end

  # Stripe refused the transfer because the destination account can't receive
  # one yet — not a real failure, just too early. The error code is the reliable
  # signal; the message is matched too because Stripe has worded this refusal
  # several ways.
  def self.destination_not_ready?(error)
    code = error.try(:code).to_s
    return true if code == "insufficient_capabilities_for_transfer"

    error.message.to_s.include?("capabilities")
  end

  # Best-effort refresh of a payee's Connect state. Never lets a Stripe hiccup
  # take down the rest of the run.
  def self.resync_payee!(payee)
    StripeConnectService.new(payee).sync_account
  rescue StandardError => e
    Rails.logger.warn("[PayoutBatchService] could not re-sync payee #{payee.class}##{payee.id}: #{e.message}")
  end

  # The Stripe charge that funded this run, how much of it is still
  # transferable, and the transfer_group already stamped on it (nil if none):
  # [charge_id, remaining_cents, charge_transfer_group].
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
  # this charge (except those paid from the balance before it), so a retry can
  # never over-commit it; items it can't cover (e.g. the credit-funded slice
  # of a run) fall back to the plain balance.
  # Best-effort: if Stripe can't tell us, transfers proceed the old way.
  def self.funding_charge_for(batch)
    return [ nil, 0, nil ] if batch.funding_payment_intent_id.blank?

    intent = Stripe::PaymentIntent.retrieve(id: batch.funding_payment_intent_id, expand: [ "latest_charge" ])
    charge = intent.latest_charge
    charge_id = charge.is_a?(String) ? charge : charge&.id
    return [ nil, 0, nil ] if charge_id.blank?

    charge_group = charge.is_a?(String) ? nil : charge.try(:transfer_group)
    # Paid from the balance before the run was funded: never drew on it.
    [ charge_id, intent.amount - batch.items.paid.where(paid_from_balance: false).sum(:amount_cents), charge_group ]
  rescue Stripe::StripeError => e
    Rails.logger.warn("[PayoutBatchService] no funding charge for batch #{batch.id}: #{e.message}")
    [ nil, 0, nil ]
  end

  # A funded run stays open until every person in it is paid: all paid →
  # completed (and only then stamped completed_at); anything still pending or
  # failed → partially_paid, waiting for #pay_remaining!.
  #
  # Finishing a paying pass tells the organization's chosen people once
  # (completion_notified_at): "everyone's paid", or who's still waiting on
  # bank details. A run that was already completed or partly paid and is
  # re-judged (a payout came back, a close-out) isn't a new completion, and
  # those have their own notices.
  FINISHED_STATUSES = %w[completed partially_paid].freeze

  def self.finalize_status!(batch)
    was_paying = !FINISHED_STATUSES.include?(batch.status)
    status = batch.items.where.not(status: "paid").none? ? "completed" : "partially_paid"
    batch.update!(status: status, completed_at: status == "completed" ? Time.current : nil)
    return batch unless was_paying && batch.completion_notified_at.nil?

    batch.update!(completion_notified_at: Time.current)
    PayoutRunCompletedNotificationJob.perform_later(batch.id, status)
    batch
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
