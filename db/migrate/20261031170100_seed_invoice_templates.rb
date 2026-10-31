# frozen_string_literal: true

class SeedInvoiceTemplates < ActiveRecord::Migration[8.0]
  def up
    InvoiceTemplates.ensure!
  end

  def down; end
end
