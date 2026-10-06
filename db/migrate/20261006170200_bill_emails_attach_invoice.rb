# frozen_string_literal: true

# The bill and receipt emails now attach CocoScout's own invoice; their words
# say so (PlatformTemplates).
class BillEmailsAttachInvoice < ActiveRecord::Migration[8.1]
  def up
    PlatformTemplates.ensure!(keys: %w[cocoscout_bill cocoscout_bill_paid], overwrite: true)
  end

  def down; end
end
