class AddUniqueIndexToSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    # solid_cable_messages is in the cable database, not the primary database
    # This migration should be skipped - the fix is handled by the rescue blocks
    # in message_service.rb
    #
    # If you need to add the index, run this directly on the cable database:
    # bin/rails db:migrate:cable
    #
    # Or connect to the cable database and run:
    # CREATE UNIQUE INDEX IF NOT EXISTS index_solid_cable_messages_on_id ON solid_cable_messages (id);
  end
end
