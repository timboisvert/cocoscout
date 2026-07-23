# frozen_string_literal: true

# Lets a contractor pay us online without a CocoScout login. The token is the
# secret in a shareable /pay/contract/:token link; the Stripe columns record what
# actually happened so the money can be traced and the org's share remitted net
# of processing fees.
class AddOnlinePaymentToContractPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :contract_payments, :payment_token, :string
    add_index  :contract_payments, :payment_token, unique: true

    add_column :contract_payments, :stripe_checkout_session_id, :string
    add_index  :contract_payments, :stripe_checkout_session_id, unique: true

    add_column :contract_payments, :stripe_payment_intent_id, :string
    add_column :contract_payments, :stripe_fee_cents, :integer
  end
end
