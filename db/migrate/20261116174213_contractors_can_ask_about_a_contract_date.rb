# frozen_string_literal: true

# A contractor asks the organization about one date on their contract (Tim,
# 2026-11-16): move it, cancel it, add one, or a plain question. One request,
# about one date, with one answer. It changes nothing by itself: only an
# amendment changes the contract. The organization answers by amending, or
# by keeping the date with a note.
class ContractorsCanAskAboutAContractDate < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_date_requests do |t|
      t.references :organization, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :contract, null: false, foreign_key: { on_delete: :cascade }
      # Empty for "add a date", and once a date the request was about is removed.
      t.references :show, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :status, null: false, default: "open"
      # What the date said when they asked, kept so the request still reads
      # right after the date moves or goes.
      t.datetime :original_at
      # The day and time asked for (move, add).
      t.datetime :proposed_at
      t.text :note
      t.references :requested_by, null: false, foreign_key: { to_table: :users, on_delete: :cascade }, index: false
      t.text :answer_note
      t.references :answered_by, foreign_key: { to_table: :users, on_delete: :nullify }, index: false
      t.datetime :answered_at
      t.datetime :closed_at
      t.datetime :reminded_at
      # When the asker cleared the answer from their page.
      t.datetime :dismissed_at
      t.timestamps
    end
    add_index :contract_date_requests, %i[organization_id status]
    # One open request to change a date; a second one replaces the first.
    # Questions sit beside it: asking one takes nothing back.
    add_index :contract_date_requests, %i[contract_id show_id], unique: true,
              where: "status IN ('open', 'amending') AND show_id IS NOT NULL AND kind <> 'question'",
              name: "index_contract_date_requests_one_open_per_date"
  end
end
