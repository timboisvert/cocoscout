class AddDefaultCastingSettingsToProductions < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :default_signup_based_casting, :boolean, default: false, null: false
    add_column :productions, :default_attendance_enabled, :boolean, default: false, null: false
  end
end
