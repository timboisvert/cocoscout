# frozen_string_literal: true

# A cast notification is the durable record that someone was told about their
# spot. It must outlive the act: removing an act from a running order used to
# cascade-destroy these rows, erasing the very evidence that a removal notice
# is owed. The role becomes nullable and Role now nullifies instead.
class AllowNullRoleOnShowCastNotifications < ActiveRecord::Migration[8.1]
  def change
    change_column_null :show_cast_notifications, :role_id, true
  end
end
