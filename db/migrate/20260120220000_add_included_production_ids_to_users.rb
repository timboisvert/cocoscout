# frozen_string_literal: true

class AddIncludedProductionIdsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :included_production_ids, :integer, array: true, default: [], null: false
  end
end
