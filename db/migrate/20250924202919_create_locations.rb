# frozen_string_literal: true

class CreateLocations < ActiveRecord::Migration[8.0]
  def change
    create_table :locations do |t|
      t.string :address1
      t.string :address2
      t.string :city
      t.string :state
      t.string :postal_code

      t.timestamps
    end
  end
end
