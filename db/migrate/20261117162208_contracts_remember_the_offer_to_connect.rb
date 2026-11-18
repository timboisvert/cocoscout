# frozen_string_literal: true

# The offer to connect a contract to the contractor's own organization
# (ContractConnections.offer!): when the contractor was notified of it
# (once), when they said "Not now" (the offer then stays as a quiet link),
# and when the organization that wrote the contract pointed it out to them
# ("Tell <contractor>", once). With the words of those two notifications.
class ContractsRememberTheOfferToConnect < ActiveRecord::Migration[8.1]
  def up
    add_column :contracts, :connect_offered_at, :datetime
    add_column :contracts, :connect_offer_dismissed_at, :datetime
    add_column :contracts, :connect_told_at, :datetime
    add_column :contracts, :connect_told_by_id, :bigint
    ContractConnectionTemplates.ensure!
  end

  def down
    remove_column :contracts, :connect_offered_at
    remove_column :contracts, :connect_offer_dismissed_at
    remove_column :contracts, :connect_told_at
    remove_column :contracts, :connect_told_by_id
  end
end
