# frozen_string_literal: true

# Books stage B: every dollar that already runs through one of CocoScout's
# two sub-ledgers reaches the organization's books from the ledger row
# itself, so no feature grows posting code of its own.
#
#   OrgCashEntry      — the "CocoScout balance" account's detail. Each row
#                       becomes one entry (kind "cash") against what the
#                       money was for: a course sale, a contract payment, a
#                       run's funding, a payee paid, money back, a
#                       correction. Rows ticketing already posted from its
#                       own services (ticket_*, top_up, a withdrawal's
#                       transfer) are left alone.
#   PayoutLedgerEntry — "Owed to performers and staff"'s detail. An earning
#                       is pay owed; a payout paid through a run is covered
#                       by the run's cash row, one paid another way comes
#                       out of the bank; a bank return and a contract
#                       deduction have their own shapes.
#
# Idempotent per row (LedgerPosting restates on change), reversed when a row
# is removed. Both models call in from after_commit and from unpost!.
class BooksPoster
  TICKETING_POSTS_ITSELF = %w[ticket_sale ticket_refund ticket_dispute ticket_exchange_out ticket_exchange_in top_up].freeze

  def self.post!(row)
    case row
    when OrgCashEntry then post_cash!(row)
    when PayoutLedgerEntry then post_owed!(row)
    end
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.error("[BooksPoster] #{row.class.name} #{row.id}: #{e.class}: #{e.message}")
  end

  def self.remove!(row)
    LedgerPosting.unpost!(source: row, kind: kind_for(row))
  rescue StandardError => e
    raise if Rails.env.test?

    Rails.logger.error("[BooksPoster] remove #{row.class.name} #{row.id}: #{e.class}: #{e.message}")
  end

  def self.kind_for(row)
    row.is_a?(OrgCashEntry) ? "cash" : "owed"
  end

  # --- The cash ledger -------------------------------------------------------

  def self.post_cash!(entry)
    return if TICKETING_POSTS_ITSELF.include?(entry.entry_type)
    return if entry.entry_type == "transfer" && entry.source_type == "BalanceWithdrawal"

    lines = cash_lines(entry)
    return if lines.nil?

    LedgerPosting.post!(organization: entry.organization, source: entry, kind: "cash",
                        entry_date: entry.occurred_at.to_date, cash_date: entry.occurred_at.to_date,
                        memo: entry.description.presence || entry.entry_type.humanize, lines: lines)
  end

  def self.cash_lines(entry)
    cents = entry.amount_cents
    balance = { account: :cocoscout_balance, amount_cents: cents }
    source = entry.source
    case entry.entry_type
    when "course_registration"
      registration = source.is_a?(CourseRegistration) ? source : nil
      amount = registration&.amount_cents.to_i
      tax = registration&.tax_cents.to_i
      production = registration&.course_offering&.production
      if registration
        # The student paid price + tax; the org nets that less whatever fees took.
        [ balance,
          { account: :course_fees, amount_cents: amount + tax - cents, production: production },
          { account: :course_income, amount_cents: -amount, production: production },
          { account: :tax_to_remit, amount_cents: -tax, production: production } ]
      else
        [ balance, { account: :course_income, amount_cents: -cents } ]
      end
    when "refund"
      registration = source.is_a?(CourseRegistration) ? source : nil
      if registration
        amount = registration.amount_cents.to_i
        tax = registration.tax_cents.to_i
        production = registration.course_offering&.production
        # cents is negative: the sale, taken back (the fees aren't).
        [ balance,
          { account: :course_income, amount_cents: amount, production: production },
          { account: :tax_to_remit, amount_cents: tax, production: production },
          { account: :course_fees, amount_cents: -(amount + tax + cents), production: production } ]
      else
        [ balance, { account: :other_income, amount_cents: -cents } ]
      end
    when "contract_payment"
      production = source.try(:contract)&.production
      [ balance, { account: :contract_income, amount_cents: -cents, production: production } ]
    when "funding"
      [ balance, { account: :bank, amount_cents: -cents } ]
    when "transfer"
      [ balance, { account: paid_out_account(source), amount_cents: -cents, **payee_dim(source) } ]
    when "transfer_reversal"
      [ balance, { account: returned_account(source), amount_cents: -cents, **payee_dim(source) } ]
    when "opening_balance", "adjustment"
      [ balance, { account: :owner_equity, amount_cents: -cents } ]
    end
  end

  # Where a transfer's money went. The org's own remittance lands in its
  # bank; a payee on a run was owed it (the run's payout ledger row says so,
  # and is skipped for that reason); a legacy course run paid an instructor
  # straight out of course money.
  def self.paid_out_account(item)
    return :bank unless item.is_a?(PayoutBatchItem)
    return :bank if item.payee_type == "Organization"
    return :instructor_pay if item.payout_batch.kind == "course"

    :owed_to_payees
  end

  # A transfer that came back into the balance: the payee's bank refused it.
  # Their payout ledger reversal already said the org owes them again, with
  # the money parked under "owed to you"; this clears that.
  def self.returned_account(item)
    return :bank unless item.is_a?(PayoutBatchItem)
    return :bank if item.payee_type == "Organization"
    return :instructor_pay if item.payout_batch.kind == "course"

    PayoutLedgerEntry.exists?(source: item, entry_type: "reversal") ? :owed_to_you : :owed_to_payees
  end

  def self.payee_dim(item)
    item.is_a?(PayoutBatchItem) && item.payee_type != "Organization" ? { payee: item.payee } : {}
  end

  # --- The payout ledger ----------------------------------------------------

  def self.post_owed!(entry)
    lines = owed_lines(entry)
    return LedgerPosting.unpost!(source: entry, kind: "owed") if lines.nil?

    LedgerPosting.post!(organization: entry.organization, source: entry, kind: "owed",
                        entry_date: entry.occurred_at.to_date, cash_date: entry.occurred_at.to_date,
                        memo: entry.description.presence || entry.entry_type.humanize, lines: lines)
  end

  def self.owed_lines(entry)
    cents = entry.amount_cents
    dims = owed_dims(entry)
    owed = { account: :owed_to_payees, amount_cents: -cents, payee: entry.payee }
    case entry.entry_type
    when "earning"
      [ { account: pay_account(entry), amount_cents: cents, **dims }, owed ]
    when "advance"
      # Money fronted before it was earned, paid out of the bank; the payee's
      # balance goes negative until earnings net it.
      [ { account: :bank, amount_cents: cents }, owed ]
    when "payout"
      # Paid through a run: the run's cash row carries it. Paid another way:
      # it came out of the bank.
      return nil if OrgCashEntry.exists?(source_type: entry.source_type, source_id: entry.source_id, entry_type: "transfer")

      [ { account: :bank, amount_cents: cents }, owed ]
    when "reversal"
      # The bank sent it back: owed again, the money parked with the payee.
      [ { account: :owed_to_you, amount_cents: cents, payee: entry.payee }, owed ]
    when "adjustment"
      [ { account: adjustment_account(entry), amount_cents: cents, **dims }, owed ]
    end
  end

  def self.pay_account(entry)
    return :staff_pay if entry.category == "staffing"

    source = entry.source
    inner = source.is_a?(PayoutContribution) ? source.source : source
    # Course money comes through course records (an offering, its payout or
    # a line of it); a show that belongs to a course is still show pay.
    return :instructor_pay if inner.class.name.to_s.start_with?("Course")
    return :contractor_pay if inner.is_a?(ContractPayment)

    :performer_pay
  end

  # A contract deduction nets services the contractor owed the org out of
  # their share: that's contract income earned.
  def self.adjustment_account(entry)
    source = entry.source
    inner = source.is_a?(PayoutContribution) ? source.source : source
    inner.is_a?(ContractPayment) ? :contract_income : :other_income
  end

  def self.owed_dims(entry)
    source = entry.source
    inner = source.is_a?(PayoutContribution) ? source.source : source
    show = inner.is_a?(Show) ? inner : inner.try(:show)
    production = inner.try(:production) || show&.production || inner.try(:course_offering)&.production || inner.try(:contract)&.production
    { show: show, production: production }.compact
  end

  private_class_method :post_cash!, :cash_lines, :paid_out_account, :returned_account, :payee_dim,
                       :post_owed!, :owed_lines, :pay_account, :adjustment_account, :owed_dims
end
