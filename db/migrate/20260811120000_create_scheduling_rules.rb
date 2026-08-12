# frozen_string_literal: true

class CreateSchedulingRules < ActiveRecord::Migration[8.0]
  def change
    create_table :scheduling_rules do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true
      t.references :house_role, null: false, foreign_key: true
      t.integer :rule_type, null: false, default: 0
      t.references :production, foreign_key: true
      t.integer :day_of_week
      t.time :starts_local_time
      t.time :ends_local_time
      t.datetime :archived_at

      t.timestamps
    end

    add_index :scheduling_rules, [ :organization_id, :archived_at ]
  end
end
