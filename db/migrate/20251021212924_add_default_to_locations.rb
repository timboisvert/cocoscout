# frozen_string_literal: true

class AddDefaultToLocations < ActiveRecord::Migration[8.0]
  def change
    add_column :locations, :default, :boolean, default: false, null: false
  end
end
