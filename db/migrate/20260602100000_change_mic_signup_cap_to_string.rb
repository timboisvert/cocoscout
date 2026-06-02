# frozen_string_literal: true

# `signup_cap` was an integer, but producers want to be able to write
# fuzzy values like "10ish" or "10-15" — capacity isn't always exact.
# Convert to a string column, preserving existing integer values as
# their text representation.
class ChangeMicSignupCapToString < ActiveRecord::Migration[8.1]
  def up
    change_column :mics, :signup_cap, :string, using: "signup_cap::text"
  end

  def down
    # Drop any non-numeric values — there's no other safe way back.
    execute <<~SQL.squish
      UPDATE mics SET signup_cap = NULL
       WHERE signup_cap !~ '^[0-9]+$'
    SQL
    change_column :mics, :signup_cap, :integer, using: "signup_cap::integer"
  end
end
