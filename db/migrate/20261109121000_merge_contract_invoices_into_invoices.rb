# frozen_string_literal: true

# One invoice system (Books V1.3, plan D2). An invoice for a contract
# payment used to be a row in contract_invoices beside the invoices an
# organization writes to anyone; both drew numbers from one counter, but
# nothing in the database kept a number from being used twice, and each had
# its own delivery, words and mailer. Now both are rows in invoices:
#
#   kind "standalone"  the invoice keeps its own lines, due date and payments
#   kind "contract"    the paper for a contract payment, which keeps the money;
#                      what it says is read from the payment (Invoice::ContractTerms)
#
# The rows are copied with their numbers, tokens, sent and receipt stamps and
# void state. contract_invoices is left in place, untouched and unused, to be
# dropped once this has run for a while.
class MergeContractInvoicesIntoInvoices < ActiveRecord::Migration[8.1]
  def up
    add_column :invoices, :kind, :string, null: false, default: "standalone"
    add_column :invoices, :contract_payment_id, :bigint
    add_column :invoices, :combined_into_payment_id, :bigint
    # A contract payment's invoice has none of these of its own.
    change_column_null :invoices, :bill_to_name, true
    change_column_null :invoices, :due_on, true
    change_column_null :invoices, :category_key, true
    add_index :invoices, :contract_payment_id, unique: true
    add_index :invoices, %i[organization_id kind]
    add_foreign_key :invoices, :contract_payments, on_delete: :nullify
    # A contract invoice carries its payment's pay-link token, kept after the
    # payment is combined away; only an organization's own invoices need
    # theirs to be the only one.
    remove_index :invoices, name: "index_invoices_on_payment_token"
    add_index :invoices, :payment_token, unique: true, where: "kind = 'standalone'", name: "index_invoices_on_payment_token"
    add_index :invoices, :payment_token, where: "kind = 'contract'", name: "index_invoices_on_contract_payment_token"

    zone = ActiveSupport::TimeZone[Rails.application.config.time_zone].tzinfo.name
    execute <<~SQL.squish
      INSERT INTO invoices (organization_id, kind, contract_payment_id, combined_into_payment_id, number, prefix, status, issued_on,
                            payment_token, sent_at, sent_count, receipt_emailed_at, voided_at, void_reason, created_at, updated_at)
      SELECT organization_id, 'contract', contract_payment_id, combined_into_payment_id, number, prefix,
             CASE WHEN voided_at IS NULL THEN 'open' ELSE 'void' END,
             (issued_at AT TIME ZONE 'UTC' AT TIME ZONE #{connection.quote(zone)})::date,
             payment_token, sent_at, sent_count, receipt_emailed_at, voided_at, void_reason, created_at, updated_at
      FROM contract_invoices
      ORDER BY id
    SQL
  end

  def down
    execute "DELETE FROM invoices WHERE kind = 'contract'"
    remove_index :invoices, name: "index_invoices_on_contract_payment_token"
    remove_index :invoices, name: "index_invoices_on_payment_token"
    add_index :invoices, :payment_token, unique: true, name: "index_invoices_on_payment_token"
    remove_foreign_key :invoices, :contract_payments
    remove_index :invoices, %i[organization_id kind]
    remove_index :invoices, :contract_payment_id
    change_column_null :invoices, :category_key, false
    change_column_null :invoices, :due_on, false
    change_column_null :invoices, :bill_to_name, false
    remove_column :invoices, :combined_into_payment_id
    remove_column :invoices, :contract_payment_id
    remove_column :invoices, :kind
  end
end
