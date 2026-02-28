class AddEventDetailsToRemoteTicketingEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :remote_ticketing_events, :event_name, :string
    add_column :remote_ticketing_events, :event_date, :datetime
    add_column :remote_ticketing_events, :venue_name, :string
  end
end
