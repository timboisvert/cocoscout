# frozen_string_literal: true

# Box office addresses a theater used before: they keep redirecting to its
# current one, and no other theater can take them.
class AddPreviousSlugsToTicketingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :ticketing_profiles, :previous_slugs, :jsonb, null: false, default: []
    add_index :ticketing_profiles, :previous_slugs, using: :gin
  end
end
