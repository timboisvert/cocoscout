# frozen_string_literal: true

# A location the organization no longer uses is archived: out of the list
# and the pickers, with everything that already points at it untouched.
class AddArchivedAtToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :archived_at, :datetime
  end
end
