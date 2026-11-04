# frozen_string_literal: true

# Tips go to whoever was working (plan §9.14): the organization's rule, the
# span each share was worked, and a register day's tips by quarter hour so
# the split reads from the day itself and never from raw orders.
class CreateTipRules < ActiveRecord::Migration[8.1]
  def change
    create_table :tip_rules do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      # { house_role_id => { "kind" => "equal" | "percent", "percent" => 15 } }
      t.jsonb :role_shares, null: false, default: {}
      t.string :nobody_on, null: false, default: "pool"
      t.timestamps
    end

    add_column :tip_shares, :worked_from, :datetime
    add_column :tip_shares, :worked_to, :datetime
    add_column :tip_shares, :source, :string, null: false, default: "typed"
    add_reference :tip_shares, :house_role, foreign_key: true

    add_column :register_days, :tips_by_time, :jsonb, null: false, default: {}
  end
end
