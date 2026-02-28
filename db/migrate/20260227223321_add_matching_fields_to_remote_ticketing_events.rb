class AddMatchingFieldsToRemoteTicketingEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :remote_ticketing_events, :suggested_show, foreign_key: { to_table: :shows }
    add_column :remote_ticketing_events, :match_confidence, :decimal, precision: 5, scale: 3
    add_column :remote_ticketing_events, :match_reasons, :jsonb, default: []
  end
end
