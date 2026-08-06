# frozen_string_literal: true

# Contracts had no versioning of any kind. Amending an executed e-sign contract
# changed the dates and the money while the signed snapshot stayed frozen, so
# the document both parties signed silently stopped describing the deal — and
# GenerateContractPdfJob early-returns forever once a signed PDF exists, so the
# PDF never caught up either.
#
# A version is an append-only record of the document at a moment: the rendered
# text, a snapshot of the deal behind it, and its own signatures.
#
# Deliberately NOT versioned: shows, rentals, payments, payouts. Those are live
# shared records. A version is history, never a restore point.
class CreateContractVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_versions do |t|
      t.references :contract, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.text :content_snapshot, null: false
      t.jsonb :deal_snapshot, null: false, default: {}
      t.references :contract_template, foreign_key: true
      t.integer :template_version
      t.boolean :requires_signature, null: false, default: true
      t.text :change_summary
      # The token THIS version went out with, so a stale link can be recognised
      # rather than 404ing at the counterparty.
      t.string :signing_token
      t.datetime :sent_for_signature_at
      t.datetime :executed_at
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :contract_versions, [ :contract_id, :version_number ], unique: true
    add_index :contract_versions, :signing_token, unique: true

    # Signatures belong to the document they actually signed. The old unique
    # index was [contract_id, signer_role] — exactly one org and one contractor
    # signature per contract, ever — which is what made re-signing impossible.
    add_reference :contract_signatures, :contract_version, foreign_key: true

    reversible do |dir|
      dir.up do
        # Every contract that has a signature gets a v1 holding what was signed.
        execute <<~SQL.squish
          INSERT INTO contract_versions (contract_id, version_number, content_snapshot, deal_snapshot,
                                         contract_template_id, template_version, requires_signature,
                                         change_summary, signing_token, sent_for_signature_at, executed_at,
                                         created_at, updated_at)
          SELECT c.id, 1,
                 COALESCE(org.content_snapshot, con.content_snapshot, ''),
                 jsonb_build_object('draft_data', COALESCE(c.draft_data, '{}'::jsonb) - 'amend',
                                    'appendixes', '[]'::jsonb),
                 COALESCE(org.contract_template_id, c.contract_template_id),
                 org.template_version, true,
                 'Original contract',
                 c.signing_token, c.sent_for_signature_at, c.executed_at,
                 COALESCE(org.signed_at, c.created_at), NOW()
          FROM contracts c
          LEFT JOIN contract_signatures org ON org.contract_id = c.id AND org.signer_role = 'organization'
          LEFT JOIN contract_signatures con ON con.contract_id = c.id AND con.signer_role = 'contractor'
          WHERE org.id IS NOT NULL OR con.id IS NOT NULL
        SQL

        execute <<~SQL.squish
          UPDATE contract_signatures s SET contract_version_id = v.id
          FROM contract_versions v
          WHERE v.contract_id = s.contract_id AND v.version_number = 1
        SQL
      end
    end

    remove_index :contract_signatures, column: [ :contract_id, :signer_role ]
    add_index :contract_signatures, [ :contract_version_id, :signer_role ],
              unique: true, name: "index_contract_signatures_on_version_and_role"
  end
end
