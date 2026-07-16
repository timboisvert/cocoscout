# frozen_string_literal: true

# Records that a production has *asked* a person to sign its agreement — whether
# sent manually by a producer or automatically on talent-pool add. This is what
# powers the "sent / awaiting / signed" roster grid: a signature says they signed,
# an agreement_request says we asked. One row per (production, person); re-sends
# bump sent_at and send_count.
class CreateAgreementRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :agreement_requests do |t|
      t.references :production, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :agreement_template, null: true, foreign_key: true
      t.references :sent_by, null: true, foreign_key: { to_table: :users }
      t.datetime :sent_at, null: false
      t.string :sent_via, null: false, default: "manual"
      t.integer :send_count, null: false, default: 1

      t.timestamps
    end

    add_index :agreement_requests, %i[production_id person_id], unique: true
  end
end
