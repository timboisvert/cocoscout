# frozen_string_literal: true

# Comp rules (Tim, 2026-11-17): comps are none or a number, so "one per
# performer" goes; and people on a contract get a rule of their own, in the
# same three places (box office, production, date). It starts at none.
#
# Plain SQL only: no app code runs here.
class CompsAreANumberAndPeopleOnAContractHaveTheirOwn < ActiveRecord::Migration[8.1]
  TABLES = %w[ticketing_profiles production_ticketings ticket_listings].freeze

  def up
    add_column :ticketing_profiles, :contract_comps_per_show, :integer, default: 0, null: false
    add_column :production_ticketings, :contract_comps_per_show, :integer
    add_column :ticket_listings, :contract_comps_per_show, :integer

    # "One per performer" becomes a set number: the one already on the row.
    TABLES.each do |table|
      execute "UPDATE #{table} SET comps_limit = 'fixed', comps_per_show = COALESCE(comps_per_show, 10) WHERE comps_limit = 'per_performer'"
      execute "UPDATE #{table} SET team_comps_limit = 'fixed', team_comps_per_show = COALESCE(team_comps_per_show, 2) WHERE team_comps_limit = 'per_performer'"
    end

    # A production or a date that already has its own rule with a set number
    # keeps it for the people on its contract: until now they could give
    # whatever the date had left, which was that number. Everything else
    # starts at none.
    %w[production_ticketings ticket_listings].each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET contract_comps_per_show = CASE WHEN comps_enabled IS NOT FALSE AND comps_limit = 'fixed' THEN COALESCE(comps_per_show, 0) ELSE 0 END
        WHERE own_comps
      SQL
    end
  end

  def down
    TABLES.each { |table| remove_column table, :contract_comps_per_show }
  end
end
