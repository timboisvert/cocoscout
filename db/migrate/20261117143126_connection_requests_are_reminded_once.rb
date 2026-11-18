# frozen_string_literal: true

# A request to connect a contract that nobody has answered gets one reminder
# after three days (ContractConnections.sweep!): when it was sent. And the
# words for a later contract that connects under a yes the organization
# already gave.
class ConnectionRequestsAreRemindedOnce < ActiveRecord::Migration[8.1]
  def up
    add_column :contract_connections, :reminded_at, :datetime
    ContractConnectionTemplates.ensure!
  end

  def down
    remove_column :contract_connections, :reminded_at
  end
end
