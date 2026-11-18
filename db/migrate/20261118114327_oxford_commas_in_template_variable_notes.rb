# frozen_string_literal: true

# Tim, 2026-11-18: "Oxford commas always." The sweep of the app's copy found
# no seeded subject or body without one; two notes beside template variables
# had lists that lacked it ("The website, the iPhone app or the Android app",
# "card, bank transfer and check"). Production already holds the old notes,
# so the three templates that carry them are written again from the code.
# ContentTemplate is the only table this reads.
class OxfordCommasInTemplateVariableNotes < ActiveRecord::Migration[8.1]
  def up
    PlatformTemplates.ensure!(keys: %w[account_deletion_requested], overwrite: true)
    InvoiceTemplates.ensure!(keys: %w[invoice invoice_reminder], overwrite: true)
  end

  def down; end
end
