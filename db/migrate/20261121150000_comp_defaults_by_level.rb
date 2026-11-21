# frozen_string_literal: true

# The comp rules as defaults by level (Tim, 2026-11-21). The box office says
# whether comps are allowed, whether there's a house limit and what it counts
# (per day or per show), what productions may issue (no limit, per show or
# per day), and whether productions on a contract have a default of their
# own. A production, and then a date, can override all of it except the
# house limit, which only the box office sets.
#
# Plain SQL, no app code. Every organization keeps what it has today:
#   - the box office's "comps per date" becomes a house limit per show;
#   - contracts already had their own number, so the box office's contracts
#     keep a default of their own (contract_comps_own);
#   - "0 per date" for contracts was "none": it becomes contract_comps off;
#   - a production's or a date's own "comps per date" is no longer theirs to
#     set, so where its production team could issue "all of them", that
#     number becomes the production team's own number instead.
class CompDefaultsByLevel < ActiveRecord::Migration[8.0]
  def up
    add_column :ticketing_profiles, :house_comps_period, :string, null: false, default: "show"
    # People on a contract start with none (Tim, 2026-11-17): a default of
    # their own, with comps off.
    add_column :ticketing_profiles, :contract_comps_own, :boolean, null: false, default: true
    add_column :ticketing_profiles, :contract_comps, :boolean, null: false, default: false
    add_column :ticketing_profiles, :contract_comps_limit, :string, null: false, default: "fixed"

    %i[production_ticketings ticket_listings].each do |table|
      add_column table, :contract_comps, :boolean
      add_column table, :contract_comps_limit, :string
    end

    # Existing contract rules carry their own number.
    change_column_default :ticketing_profiles, :contract_comps_per_show, from: 0, to: 4

    execute <<~SQL
      UPDATE ticketing_profiles
         SET contract_comps_own = TRUE,
             contract_comps = (contract_comps_per_show > 0),
             contract_comps_per_show = CASE WHEN contract_comps_per_show > 0 THEN contract_comps_per_show ELSE 4 END
    SQL

    %w[production_ticketings ticket_listings].each do |table|
      execute <<~SQL
        UPDATE #{table}
           SET contract_comps = (COALESCE(contract_comps_per_show, 0) > 0),
               contract_comps_limit = 'fixed',
               contract_comps_per_show = CASE WHEN COALESCE(contract_comps_per_show, 0) > 0 THEN contract_comps_per_show ELSE 4 END
         WHERE own_comps = TRUE
      SQL
      execute <<~SQL
        UPDATE #{table}
           SET team_comps_limit = 'fixed', team_comps_per_show = comps_per_show
         WHERE own_comps = TRUE AND comps_limit = 'fixed' AND COALESCE(team_comps_limit, 'all') = 'all' AND comps_per_show IS NOT NULL
      SQL
      execute "UPDATE #{table} SET comps_limit = NULL, comps_per_show = NULL"
    end
  end

  def down
    %i[production_ticketings ticket_listings].each do |table|
      remove_column table, :contract_comps_limit
      remove_column table, :contract_comps
    end
    change_column_default :ticketing_profiles, :contract_comps_per_show, from: 4, to: 0
    remove_column :ticketing_profiles, :contract_comps_limit
    remove_column :ticketing_profiles, :contract_comps
    remove_column :ticketing_profiles, :contract_comps_own
    remove_column :ticketing_profiles, :house_comps_period
  end
end
