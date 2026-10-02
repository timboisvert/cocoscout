# frozen_string_literal: true

# Buyers get a reminder a few days before their show — how many is the
# theater's call (Ticketing settings → Box office; blank means none). Each
# order is reminded once, and a buyer can stop them for their order.
class AddTicketReminders < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :reminder_days_before, :integer, default: 1
    add_column :ticket_orders, :reminded_at, :datetime
    add_column :ticket_orders, :reminders_opt_out, :boolean, default: false, null: false
  end
end
