# frozen_string_literal: true

# Ties a line of the Stripe balance (StripeBalanceTransaction) to the
# CocoScout record that caused it, and checks the amount against what that
# record says. Works from the ids saved on the row, so a line imported
# before its record existed (an invoice synced later) matches on the next
# pass.
class StripeTransactionMatcher
  # Lines that belong to CocoScout itself and need no record.
  OWN_CATEGORIES = { "payout" => "payout_to_bank", "payout_reversal" => "payout_to_bank",
                     "topup" => "added_from_bank", "topup_reversal" => "added_from_bank",
                     "fee" => "stripe_fee", "platform_earning" => "other_income" }.freeze

  def self.apply!(row)
    category, record, expected = classify(row)
    row.category = category
    row.matched = record
    row.organization = organization_for(record)
    row.expected_cents = expected
    row.match_status =
      if category == "unknown" || (record.nil? && !OWN_CATEGORIES.value?(category))
        "unmatched"
      elsif expected && expected != row.amount_cents
        "mismatch"
      else
        "matched"
      end
    row
  end

  # Re-run matching on the lines still waiting for a record.
  def self.rematch_pending!
    StripeBalanceTransaction.where(match_status: %w[unmatched mismatch]).find_each do |row|
      apply!(row)
      row.save! if row.changed?
    end
  end

  def self.classify(row)
    refs = row.refs || {}
    case row.reporting_category
    when "charge" then charge(refs)
    # A bank debit that bounced: tied to the same record, so the two lines
    # cancel. Its amount is the charge's, negated, so it isn't checked.
    when "charge_failure"
      category, record, = charge(refs)
      [ category, record, nil ]
    when "refund" then refund(row, refs)
    when "transfer" then transfer(row.source_id, row.amount_cents)
    when "transfer_reversal" then reversal(refs)
    when "dispute", "dispute_reversal" then dispute(refs)
    else
      own = OWN_CATEGORIES[row.reporting_category] || (row.txn_type == "stripe_fee" ? "stripe_fee" : nil)
      [ own || "unknown", nil, nil ]
    end
  end

  def self.charge(refs)
    pi = refs["payment_intent"]
    if pi.present?
      if (order = TicketOrder.where(stripe_payment_intent_id: pi, exchanged_from_id: nil).order(:id).first)
        # A checkout with several shows is one charge for all of them.
        return [ "ticket_order", order, order.ticket_purchase&.total_cents || order.total_cents ]
      end
      if (registration = CourseRegistration.find_by(stripe_payment_intent_id: pi))
        return [ "course_registration", registration, registration.amount_cents + registration.tax_cents.to_i ]
      end
      if (payment = ContractPayment.find_by(stripe_payment_intent_id: pi))
        return [ "contract_payment", payment, payment.amount_cents ]
      end
      if (top_up = BalanceTopUp.find_by(stripe_payment_intent_id: pi))
        return [ "top_up", top_up, top_up.amount_cents ]
      end
      if (batch = PayoutBatch.find_by(funding_payment_intent_id: pi))
        funded = OrgCashEntry.find_by(source: batch, entry_type: "funding")&.amount_cents
        return [ "run_funding", batch, funded ]
      end
      if (invoice = BillingInvoice.find_by(stripe_payment_intent_id: pi))
        return [ "billing", invoice, invoice.amount_due_cents ]
      end
    end
    if refs["invoice"].present? && (invoice = BillingInvoice.find_by(stripe_invoice_id: refs["invoice"]))
      return [ "billing", invoice, invoice.amount_due_cents ]
    end
    [ "unknown", nil, nil ]
  end

  def self.refund(row, refs)
    if (refund = TicketRefund.find_by(stripe_refund_id: row.source_id))
      return [ "ticket_refund", refund, -refund.amount_cents ]
    end
    registration = CourseRegistration.find_by(stripe_refund_id: row.source_id) ||
                   (refs["payment_intent"].present? && CourseRegistration.find_by(stripe_payment_intent_id: refs["payment_intent"], status: "refunded"))
    if registration
      return [ "course_refund", registration, -(registration.amount_cents + registration.tax_cents.to_i) ]
    end
    # A bill given back (a refund or a credit note refunding it): can be
    # partial, so its amount isn't checked.
    if refs["payment_intent"].present? && (invoice = BillingInvoice.find_by(stripe_payment_intent_id: refs["payment_intent"]))
      return [ "billing_refund", invoice, nil ]
    end
    [ "unknown", nil, nil ]
  end

  def self.transfer(transfer_id, amount_cents)
    return [ "unknown", nil, nil ] if transfer_id.blank?

    if (withdrawal = BalanceWithdrawal.find_by(stripe_transfer_id: transfer_id))
      return [ "withdrawal", withdrawal, -withdrawal.amount_cents ]
    end
    if (item = PayoutBatchItem.find_by(stripe_transfer_id: transfer_id))
      return [ "payee_transfer", item, -item.amount_cents ]
    end
    [ "unknown", nil, nil ]
  end

  # A reversal can be partial, so its amount isn't checked.
  def self.reversal(refs)
    transfer_id = refs["transfer"]
    record = BalanceWithdrawal.find_by(stripe_transfer_id: transfer_id) || PayoutBatchItem.find_by(stripe_transfer_id: transfer_id) if transfer_id.present?
    [ record ? "transfer_reversal" : "unknown", record, nil ]
  end

  def self.dispute(refs)
    order = TicketOrder.where(stripe_payment_intent_id: refs["payment_intent"]).order(:id).first if refs["payment_intent"].present?
    order ||= TicketOrder.where(stripe_charge_id: refs["charge"]).order(:id).first if refs["charge"].present?
    [ order ? "dispute" : "unknown", order, nil ]
  end

  def self.organization_for(record)
    case record
    when nil then nil
    when ContractPayment then record.contract&.organization
    else record.try(:organization)
    end
  end

  private_class_method :classify, :charge, :refund, :transfer, :reversal, :dispute
end
