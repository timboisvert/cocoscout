# frozen_string_literal: true

# Which of a production's dates are cast, said the way Ticketing says which
# dates it sells (Tim, 2026-11-18: "all events, just events of the following
# type, or types... or only specific dates. Like ticketing got this right."):
#
#   all          every show, class, workshop, and open mic, never rehearsals
#                or meetings (what a new date already did, so every
#                production starts here and nothing changes)
#   event_types  only the kinds in casting_event_type_filter
#   manual       only the dates picked; the picks are each date's own switch
#                (shows.casting_enabled), so there is nothing else to store
#
# The same two columns, by the same names, as production_ticketings'
# event_matching and event_type_filter.
class ProductionsSayWhichDatesAreCast < ActiveRecord::Migration[8.1]
  def change
    add_column :productions, :casting_event_matching, :string, default: "all", null: false
    add_column :productions, :casting_event_type_filter, :jsonb, default: [], null: false
  end
end
