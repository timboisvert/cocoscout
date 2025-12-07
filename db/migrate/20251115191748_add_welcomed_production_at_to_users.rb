# frozen_string_literal: true

class AddWelcomedProductionAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :welcomed_production_at, :datetime
  end
end
