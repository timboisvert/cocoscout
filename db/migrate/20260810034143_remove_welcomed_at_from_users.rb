# frozen_string_literal: true

# users.welcomed_at was never read or written by app code (the live flags are
# users.welcomed_production_at and people.profile_welcomed_at).
class RemoveWelcomedAtFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :welcomed_at, :datetime
  end
end
