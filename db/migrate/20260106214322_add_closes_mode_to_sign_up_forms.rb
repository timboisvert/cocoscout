class AddClosesModeToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    # closes_mode: "event_start", "event_end", "before", "after", "manual"
    add_column :sign_up_forms, :closes_mode, :string, default: "event_start", null: false
    # closes_offset_value: numeric value for before/after mode
    add_column :sign_up_forms, :closes_offset_value, :integer, default: 0
    # closes_offset_unit: "hours" or "days" for before/after mode
    add_column :sign_up_forms, :closes_offset_unit, :string, default: "hours"
  end
end
