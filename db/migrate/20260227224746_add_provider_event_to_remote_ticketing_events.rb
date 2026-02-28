class AddProviderEventToRemoteTicketingEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :remote_ticketing_events, :provider_event, null: false, foreign_key: true
  end
end
