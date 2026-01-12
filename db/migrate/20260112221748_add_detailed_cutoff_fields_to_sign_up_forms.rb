class AddDetailedCutoffFieldsToSignUpForms < ActiveRecord::Migration[8.1]
  def change
    # Edit cutoff fields - toggle is OFF by default (edit_cutoff_mode = nil means no cutoff)
    # When enabled: at_event (default), before_event, or after_event
    add_column :sign_up_forms, :edit_cutoff_mode, :string, default: nil
    add_column :sign_up_forms, :edit_cutoff_days, :integer, default: 0
    add_column :sign_up_forms, :edit_cutoff_minutes, :integer, default: 0
    # Note: edit_cutoff_hours already exists in the schema

    # Cancel cutoff fields - toggle is OFF by default (cancel_cutoff_mode = nil means no cutoff)
    # When enabled: at_event (default), before_event, or after_event
    add_column :sign_up_forms, :cancel_cutoff_mode, :string, default: nil
    add_column :sign_up_forms, :cancel_cutoff_days, :integer, default: 0
    add_column :sign_up_forms, :cancel_cutoff_minutes, :integer, default: 0
    # Note: cancel_cutoff_hours already exists in the schema

    # Opens timing: x days, y hours, z minutes before event (default: 7 days, 0 hours, 0 minutes)
    add_column :sign_up_forms, :opens_hours_before, :integer, default: 0
    add_column :sign_up_forms, :opens_minutes_before, :integer, default: 0
    # Note: opens_days_before already exists in the schema with default 7

    # Closes timing: add minutes for granularity (closes_offset_value/closes_offset_unit already exist)
    add_column :sign_up_forms, :closes_minutes_offset, :integer, default: 0
  end
end
