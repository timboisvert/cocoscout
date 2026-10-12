# frozen_string_literal: true

# Bank setup links are emailed to the payee and never shown to managers (Tim,
# 2026-10-12): a manager who could copy one could open it and connect their
# own bank to someone else's payouts. Each send is recorded so the page can
# say "Sent Oct 12" and offer Resend. Also seeds the email's words.
class CreateBankSetupEmails < ActiveRecord::Migration[8.1]
  def up
    create_table :bank_setup_emails do |t|
      t.references :organization, null: false, foreign_key: true, index: false
      t.string :payee_type, null: false
      t.bigint :payee_id, null: false
      t.string :email, null: false
      t.references :sent_by, foreign_key: { to_table: :users }, index: false
      t.timestamps
    end
    add_index :bank_setup_emails, %i[organization_id payee_type payee_id], name: "idx_bank_setup_emails_payee"

    PlatformTemplates.ensure!(keys: [ "payee_bank_setup_link" ])
  end

  def down
    drop_table :bank_setup_emails
    ContentTemplate.where(key: "payee_bank_setup_link").delete_all
  end
end
