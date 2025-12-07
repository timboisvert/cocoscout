# frozen_string_literal: true

class CreateShows < ActiveRecord::Migration[8.0]
  def change
    create_table :shows do |t|
      t.string :secondary_name
      t.datetime :date_and_time

      t.timestamps
    end
  end
end
