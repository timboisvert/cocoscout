# frozen_string_literal: true

# Work availability stored as real time intervals instead of region names.
#
# staff_unavailabilities holds one row per person per date naming a region
# ("evening"): it can't say "free after 8:30", can't hold two blocks in a day,
# has no recurrence, and is read against a shift's START time only. This is the
# replacement. Every entry is a band of minutes on a set of days:
#
#   kind      weekly (day_of_week, optionally bounded by starts_on/ends_on)
#             or dated (starts_on..ends_on, a single date being a 1-day range)
#   polarity  available | unavailable — signed entries instead of one global
#             destructive mode flag
#   minutes   starts_minute..ends_minute from local midnight; all day is 0..1440
#             and a band past midnight simply runs above 1440 (10pm–2am is
#             1320..1560), so there is no wrap-around rule to carry
#
# Integer minutes rather than a range type on purpose: a weekly entry has no
# timestamps to put in a tstzrange, and an exclusion constraint would forbid
# the overlap this model relies on ("weekday evenings" alongside "not this
# Thursday"). No unique index for the same reason.
#
# people.availability_confirmed_through records how far ahead someone has said
# their availability is right, so "never answered" can finally be told apart
# from "said they're free".
class CreateStaffAvailabilityEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_availability_entries do |t|
      t.references :person, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.integer :polarity, null: false, default: 0
      t.integer :day_of_week
      t.date :starts_on
      t.date :ends_on
      t.integer :starts_minute, null: false, default: 0
      t.integer :ends_minute, null: false, default: 1440
      t.string :note, limit: 140
      t.integer :source, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.timestamps

      t.check_constraint "ends_minute > starts_minute", name: "staff_availability_band_forward"
      t.check_constraint "starts_minute BETWEEN 0 AND 1440", name: "staff_availability_starts_in_day"
      t.check_constraint "ends_minute BETWEEN 1 AND 2880", name: "staff_availability_ends_within_next_day"
      t.check_constraint "starts_on IS NULL OR ends_on IS NULL OR ends_on >= starts_on",
                         name: "staff_availability_dates_forward"
      t.check_constraint "(kind = 0 AND day_of_week BETWEEN 0 AND 6) OR " \
                         "(kind = 1 AND day_of_week IS NULL AND starts_on IS NOT NULL AND ends_on IS NOT NULL)",
                         name: "staff_availability_kind_shape"
    end

    add_index :staff_availability_entries, [ :person_id, :kind ]
    add_index :staff_availability_entries, [ :person_id, :starts_on, :ends_on ],
              where: "kind = 1", name: "idx_staff_availability_dated_span"

    add_column :people, :availability_confirmed_through, :date
  end
end
