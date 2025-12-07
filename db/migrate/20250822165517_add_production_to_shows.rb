# frozen_string_literal: true

class AddProductionToShows < ActiveRecord::Migration[8.0]
  def change
    add_reference :shows, :production, null: false, foreign_key: true
  end
end
