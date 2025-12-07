# frozen_string_literal: true

class RemoveVenueFromPerformanceCredits < ActiveRecord::Migration[8.1]
  def change
    remove_column :performance_credits, :venue, :string
  end
end
