# frozen_string_literal: true

# Choosing Pro monthly (Tim, 2026-11-01: one bill a month, the plan beside
# the usage): Stripe's checkout saves the organization's card or bank (a setup
# session, nothing charged), that becomes what its monthly bill is paid from,
# and Pro starts on the monthly bill. From the success page, and again from
# the checkout webhook; starting twice changes nothing.
class ProMonthlyStart
  KIND = "pro_monthly"

  def self.session_params(organization, success_url:, cancel_url:)
    meta = { organization_id: organization.id, kind: KIND }
    { mode: "setup", currency: "usd", customer: organization.stripe_customer_id,
      success_url: success_url, cancel_url: cancel_url, metadata: meta, setup_intent_data: { metadata: meta } }
  end

  def self.from_session!(organization, session)
    return false unless session.mode == "setup" && session.metadata["kind"] == KIND
    return false unless session.metadata["organization_id"].to_i == organization.id
    return true if organization.pro_on_monthly_bill?

    intent_id = session.setup_intent.is_a?(String) ? session.setup_intent : session.setup_intent&.id
    payment_method = intent_id && Stripe::SetupIntent.retrieve(intent_id).payment_method
    payment_method = payment_method.id if payment_method.respond_to?(:id)
    if payment_method.present?
      Stripe::Customer.update(organization.stripe_customer_id, invoice_settings: { default_payment_method: payment_method })
    end
    organization.start_pro_on_monthly_bill!
    true
  end
end
