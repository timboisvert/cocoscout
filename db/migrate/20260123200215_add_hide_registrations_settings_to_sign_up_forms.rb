class AddHideRegistrationsSettingsToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    # hide_registrations_mode: "event_start" (default), "after_event", "never"
    add_column :sign_up_forms, :hide_registrations_mode, :string, default: "event_start"
    # For "after_event" mode: how long after the event starts to hide names
    add_column :sign_up_forms, :hide_registrations_offset_value, :integer, default: 2
    add_column :sign_up_forms, :hide_registrations_offset_unit, :string, default: "hours"
  end
end
