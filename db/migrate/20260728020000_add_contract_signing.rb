# frozen_string_literal: true

# Native e-signature state for contracts, plus the signature records themselves.
# Only meaningful for signing_mode: esign contracts; offline contracts stay unsent.
#
#   signing_state: unsent → out_for_signature → executed
#   signing_token: DB-backed and ROTATABLE — revoking a request nulls it so the
#                  old link dies; the next send mints a fresh one.
class AddContractSigning < ActiveRecord::Migration[8.1]
  def change
    add_column :contracts, :signing_state, :string, null: false, default: "unsent"
    add_column :contracts, :signing_token, :string
    add_column :contracts, :sent_for_signature_at, :datetime
    add_column :contracts, :executed_at, :datetime
    add_index  :contracts, :signing_token, unique: true

    create_table :contract_signatures do |t|
      t.references :contract, null: false, foreign_key: true
      t.string  :signer_role, null: false            # organization | contractor
      t.string  :signer_name
      t.string  :signer_email
      t.references :person, null: true, foreign_key: true
      t.bigint :signed_by_user_id                    # org-side: the producer who sent it
      t.references :contract_template, null: true, foreign_key: true
      t.datetime :signed_at, null: false
      t.string  :ip_address
      t.text    :user_agent
      t.text    :content_snapshot, null: false        # exact document agreed to
      t.integer :template_version

      t.timestamps
    end

    # At most one signature per role per contract (org + contractor). Revoke
    # deletes the org row before a re-send recreates it, so this never fights us.
    add_index :contract_signatures, [ :contract_id, :signer_role ], unique: true
    add_index :contract_signatures, :signed_by_user_id
  end
end
