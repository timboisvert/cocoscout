# frozen_string_literal: true

# A theater's monthly CocoScout statement: what it paid CocoScout, and what
# happened to its CocoScout balance. Made on the 1st for the month before,
# kept with its PDF, emailed to the owner once.
class CreateOrgStatements < ActiveRecord::Migration[8.1]
  def change
    create_table :org_statements do |t|
      t.references :organization, null: false, foreign_key: true
      t.date :month, null: false
      t.jsonb :totals, null: false, default: {}
      t.datetime :generated_at
      t.datetime :emailed_at
      t.timestamps
    end
    add_index :org_statements, %i[organization_id month], unique: true
  end
end
