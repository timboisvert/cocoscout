class AddWebhookLastReceivedAtToTicketingProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_providers, :webhook_last_received_at, :datetime
  end
end
