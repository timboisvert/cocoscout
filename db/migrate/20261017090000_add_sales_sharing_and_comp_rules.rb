# frozen_string_literal: true

# Ticket sales beyond the organization's managers (2026-10-17): who sees
# them (Ticketing settings → Who sees sales), the comp rules (Ticketing
# settings → Comps, with a production's and a date's own), and whether staff
# see how many people to expect on their shifts (Staffing settings →
# Ticketing).
class AddSalesSharingAndCompRules < ActiveRecord::Migration[8.1]
  def change
    change_table :ticketing_profiles, bulk: true do |t|
      # What a production team manager, a production team viewer and the
      # cast see of a production's sales (TicketSalesAccess levels).
      t.string :team_manager_sales, null: false, default: "everything"
      t.string :team_viewer_sales, null: false, default: "numbers"
      t.string :cast_sales, null: false, default: "production_cast"
      # The box office's comp rules: on at all; how many a date can give
      # away (unlimited | fixed | per_performer); whether production team
      # managers give some, and how many (all | fixed | per_performer).
      t.boolean :comps_enabled, null: false, default: true
      t.string :comps_limit, null: false, default: "unlimited"
      t.integer :comps_per_show, null: false, default: 10
      t.boolean :team_comps, null: false, default: true
      t.string :team_comps_limit, null: false, default: "all"
      t.integer :team_comps_per_show, null: false, default: 2
    end

    # A production's own comp rules (own_comps on), and a date's own again.
    %i[production_ticketings ticket_listings].each do |table|
      change_table table, bulk: true do |t|
        t.boolean :own_comps, null: false, default: false
        t.boolean :comps_enabled
        t.string :comps_limit
        t.integer :comps_per_show
        t.boolean :team_comps
        t.string :team_comps_limit
        t.integer :team_comps_per_show
      end
    end

    add_column :organizations, :staff_see_ticket_counts, :boolean, null: false, default: true
  end
end
