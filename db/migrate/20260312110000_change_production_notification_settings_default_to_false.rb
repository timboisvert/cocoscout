# frozen_string_literal: true

class ChangeProductionNotificationSettingsDefaultToFalse < ActiveRecord::Migration[8.0]
  def change
    change_column_default :production_notification_settings, :enabled, from: true, to: false
  end
end
