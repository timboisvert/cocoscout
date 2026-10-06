# frozen_string_literal: true

# The words of the invoice, reminder and receipt emails (ContractInvoiceTemplates).
class SeedContractInvoiceTemplates < ActiveRecord::Migration[8.1]
  def up
    ContractInvoiceTemplates.ensure!
  end

  def down
    ContentTemplate.where(key: ContractInvoiceTemplates::TEMPLATES.map { |t| t[:key] }).delete_all
  end
end
