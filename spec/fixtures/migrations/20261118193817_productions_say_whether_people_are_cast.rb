# frozen_string_literal: true

# Each production is marked (Tim, 2026-11-18): "We cast people in this
# production" or "We don't cast people in this production". Until now the
# only switch was on each date (shows.casting_enabled), so nothing said
# whether a production is one that gets cast at all.
#
# The answer for the productions that already exist is read from what they
# have. No date's own casting switch is changed here.
#
#   casts_people is false only for a production that has dates, has casting
#   off on every one of them, and has no roles (the Attendees role a sign-up
#   form makes for itself isn't one). Everything else keeps the
#   default, true: a production with roles, with anyone cast, with any date
#   that has casting on, or with no dates yet.
#
# casting_setup_completed was written by four paths and read by none. It is
# reused as "casting is set up", which the casting board reads from now on.
# Two corrections make the old values true:
#
#   - A production with roles, or with anyone cast, is set up, however it
#     was made.
#   - The first production made when an organization signs up (producer
#     set-up) was stamped as set up though nothing about casting was asked.
#     One made within a minute of its organization, with no roles and nobody
#     cast, goes back to not set up.
#
# Plain SQL throughout: no app code, so the order among other migrations
# doesn't matter.
class ProductionsSayWhetherPeopleAreCast < ActiveRecord::Migration[8.1]
  def up
    add_column :productions, :casts_people, :boolean, default: true, null: false
    backfill
  end

  def down
    remove_column :productions, :casts_people
  end

  # The three statements above, on their own so they can be run against a
  # database that already has the column (spec/migrations).
  def backfill
    execute <<~SQL.squish
      UPDATE productions
      SET casts_people = FALSE
      WHERE EXISTS (SELECT 1 FROM shows WHERE shows.production_id = productions.id)
        AND NOT EXISTS (SELECT 1 FROM shows WHERE shows.production_id = productions.id AND shows.casting_enabled)
        AND NOT EXISTS (SELECT 1 FROM roles WHERE roles.production_id = productions.id AND NOT roles.system_managed)
    SQL

    execute <<~SQL.squish
      UPDATE productions
      SET casting_setup_completed = TRUE
      WHERE casting_setup_completed = FALSE
        AND (EXISTS (SELECT 1 FROM roles WHERE roles.production_id = productions.id AND NOT roles.system_managed)
             OR EXISTS (SELECT 1 FROM show_person_role_assignments assignments
                        JOIN shows ON shows.id = assignments.show_id
                        WHERE shows.production_id = productions.id))
    SQL

    execute <<~SQL.squish
      UPDATE productions
      SET casting_setup_completed = FALSE
      FROM organizations
      WHERE organizations.id = productions.organization_id
        AND productions.casting_setup_completed = TRUE
        AND productions.production_type = 'in_house'
        AND productions.created_at <= organizations.created_at + INTERVAL '1 minute'
        AND NOT EXISTS (SELECT 1 FROM roles WHERE roles.production_id = productions.id AND NOT roles.system_managed)
        AND NOT EXISTS (SELECT 1 FROM show_person_role_assignments assignments
                        JOIN shows ON shows.id = assignments.show_id
                        WHERE shows.production_id = productions.id)
    SQL
  end
end
