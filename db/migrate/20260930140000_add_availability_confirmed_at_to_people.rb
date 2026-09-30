# frozen_string_literal: true

# When a person last pressed "Confirm my availability" — so a manager can see
# not just that someone's availability is up to date, but when they said so.
# availability_confirmed_through (how far ahead it counts) stays as it is.
class AddAvailabilityConfirmedAtToPeople < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :availability_confirmed_at, :datetime
  end
end
