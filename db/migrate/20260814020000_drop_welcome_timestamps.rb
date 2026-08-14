# frozen_string_literal: true

# The old welcome takeovers (manage "Start Producing", profile welcome page,
# my-dashboard hero) are gone, replaced by dismissible intro guides whose state
# lives in users.dismissed_guides. Nothing reads these columns anymore.
class DropWelcomeTimestamps < ActiveRecord::Migration[8.0]
  def change
    remove_column :people, :profile_welcomed_at, :datetime
    remove_column :users, :welcomed_production_at, :datetime
  end
end
