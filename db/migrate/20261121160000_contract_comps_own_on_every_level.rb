# frozen_string_literal: true

# Productions on a contract are a subset of productions (Tim, 2026-11-21:
# "they're not peers"), at all three levels: a production's or a date's own
# rules also say whether its contractor has a limit of their own, or follows
# the production's. Own rules made before this gave the contractor their own
# numbers, so they keep them. Plain SQL, no app code.
class ContractCompsOwnOnEveryLevel < ActiveRecord::Migration[8.0]
  def up
    %i[production_ticketings ticket_listings].each do |table|
      add_column table, :contract_comps_own, :boolean
      execute "UPDATE #{table} SET contract_comps_own = TRUE WHERE own_comps = TRUE"
    end
  end

  def down
    %i[production_ticketings ticket_listings].each { |table| remove_column table, :contract_comps_own }
  end
end
