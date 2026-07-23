# frozen_string_literal: true

# The org's default answer to "how may a contractor pay us?" Online is always
# available; this records which offline methods are also accepted (a mailed
# check, a direct bank transfer, cash). Each contract inherits this and can
# loosen or tighten it for that one deal.
class AddDefaultContractPaymentMethodsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :default_contract_payment_methods, :jsonb, default: [ "online" ], null: false
  end
end
