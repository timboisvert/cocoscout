# frozen_string_literal: true

# The words of a contract payment's invoice, reminder and receipt emails
# (InvoiceTemplates, which has kept them since the two invoice systems
# became one).
class SeedContractInvoiceTemplates < ActiveRecord::Migration[8.1]
  KEYS = %w[contract_invoice contract_invoice_reminder contract_payment_receipt].freeze

  def up
    InvoiceTemplates.ensure!(keys: KEYS)
  end

  def down
    ContentTemplate.where(key: KEYS).delete_all
  end
end
