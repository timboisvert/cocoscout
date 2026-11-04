# frozen_string_literal: true

# A suggested bank rule the organization said no to (Books V1.3, plan D3;
# Tim, 2026-11-02), so it isn't suggested again.
class CreateBankRuleDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_rule_dismissals do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :phrase, null: false
      t.string :direction, null: false, default: "any"
      t.references :dismissed_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :bank_rule_dismissals, %i[organization_id phrase direction], unique: true, name: "index_bank_rule_dismissals_on_org_phrase_direction"
  end
end
