# frozen_string_literal: true

# A notice a manager put their own words in is both: a Notification (the
# fact) and a Message from them (the words). message is that thread, so
# opening it marks the notification read too.
class AddMessageToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_reference :notifications, :message, foreign_key: { on_delete: :nullify }
  end
end
