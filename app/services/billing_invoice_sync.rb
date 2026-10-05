# frozen_string_literal: true

# Mirrors Stripe's invoices to BillingInvoice: from the invoice webhooks as
# they happen, and nightly for every org with a Stripe customer, so a missed
# webhook can't leave a bill unrecorded. Works across Stripe API versions:
# newer ones put the subscription under parent.subscription_details, the
# payment under payments, and a line's price under pricing.price_details.
class BillingInvoiceSync
  def self.sync!(invoice, organization: nil)
    # Read as a plain hash: the gem raises on fields newer API versions
    # removed (invoice.payment_intent, invoice.subscription).
    invoice = plain(invoice)
    organization ||= Organization.find_by(stripe_customer_id: invoice["customer"])
    return nil unless organization

    record = BillingInvoice.find_or_initialize_by(stripe_invoice_id: invoice["id"])
    record.assign_attributes(
      organization: organization,
      stripe_subscription_id: subscription_id(invoice),
      stripe_payment_intent_id: payment_intent_id(invoice) || record.stripe_payment_intent_id,
      number: invoice["number"],
      kind: kind_for(invoice, organization),
      status: invoice["status"].presence || "draft",
      period_start: time(invoice["period_start"]),
      period_end: time(invoice["period_end"]),
      amount_due_cents: invoice["amount_due"].to_i,
      amount_paid_cents: invoice["amount_paid"].to_i,
      amount_remaining_cents: invoice["amount_remaining"].to_i,
      lines: lines_of(invoice),
      hosted_invoice_url: invoice["hosted_invoice_url"],
      invoice_pdf_url: invoice["invoice_pdf"],
      finalized_at: time(invoice.dig("status_transitions", "finalized_at")) || record.finalized_at,
      paid_at: time(invoice.dig("status_transitions", "paid_at")) || record.paid_at
    )
    record.save! if record.changed?
    # A charge imported before its bill was known can match now.
    if record.stripe_payment_intent_id.present?
      StripeBalanceTransaction.where(match_status: "unmatched").where("refs->>'payment_intent' = ?", record.stripe_payment_intent_id).find_each do |row|
        StripeTransactionMatcher.apply!(row)
        row.save! if row.changed?
      end
    end
    record
  end

  # A payment attempt failed: say so on the bill.
  def self.payment_failed!(invoice)
    record = sync!(invoice)
    return unless record

    error = plain(invoice)["last_finalization_error"]
    record.update!(failed_at: Time.current, failure_message: error.is_a?(Hash) && error["message"].presence || "The payment didn't go through.")
  end

  def self.plain(object)
    hash = object.respond_to?(:to_hash) ? object.to_hash : object
    hash.respond_to?(:deep_stringify_keys) ? hash.deep_stringify_keys : {}
  end

  # Every invoice of every org Stripe knows as a customer.
  def self.sync_all!
    Organization.where.not(stripe_customer_id: nil).find_each do |organization|
      Stripe::Invoice.list({ customer: organization.stripe_customer_id, limit: 100, expand: [ "data.payments" ] })
                     .auto_paging_each { |invoice| sync!(invoice, organization: organization) }
    rescue Stripe::StripeError => e
      Rails.logger.warn("[BillingInvoiceSync] org #{organization.id}: #{e.message}")
    end
  end

  # Stripe ids may arrive as a string or as the expanded object.
  def self.id_of(value)
    value.is_a?(Hash) ? value["id"] : value.presence
  end

  def self.subscription_id(invoice)
    id_of(invoice.dig("parent", "subscription_details", "subscription")) || id_of(invoice["subscription"])
  end

  def self.payment_intent_id(invoice)
    Array(invoice.dig("payments", "data")).each do |payment|
      pi = id_of(payment.dig("payment", "payment_intent"))
      return pi if pi
    end
    id_of(invoice["payment_intent"])
  end

  # Usage bills carry the metered prices; Pro bills the plan's.
  def self.kind_for(invoice, organization)
    prices = price_ids(invoice)
    usage = [ SubscriptionPlan.staff_active_price_id, SubscriptionPlan.performer_active_price_id ].compact
    pro = [ SubscriptionPlan.monthly_price_id, SubscriptionPlan.annual_price_id ].compact
    return "usage" if prices.intersect?(usage)
    return "pro" if prices.intersect?(pro)

    subscription = subscription_id(invoice)
    return "usage" if subscription.present? && subscription == organization.staffing_subscription_id
    return "pro" if subscription.present? && subscription == organization.stripe_subscription_id

    "other"
  end

  def self.price_ids(invoice)
    line_items(invoice).filter_map { |line| id_of(line.dig("pricing", "price_details", "price")) || id_of(line["price"]) }
  end

  def self.lines_of(invoice)
    line_items(invoice).map do |line|
      { "description" => line["description"], "quantity" => line["quantity"], "amount_cents" => line["amount"].to_i }
    end
  end

  def self.line_items(invoice)
    Array(invoice.dig("lines", "data"))
  end

  def self.time(value)
    value.present? ? Time.zone.at(value.to_i) : nil
  end

  private_class_method :plain, :id_of, :subscription_id, :payment_intent_id, :kind_for, :price_ids, :lines_of, :line_items, :time
end
