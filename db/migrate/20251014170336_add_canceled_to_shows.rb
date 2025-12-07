# frozen_string_literal: true

class AddCanceledToShows < ActiveRecord::Migration[8.0]
  def change
    add_column :shows, :canceled, :boolean, default: false, null: false
  end
end
