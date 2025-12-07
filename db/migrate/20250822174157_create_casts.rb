# frozen_string_literal: true

class CreateCasts < ActiveRecord::Migration[8.0]
  def change
    create_table :casts do |t|
      t.references :production, null: false, foreign_key: true
      t.string :name

      t.timestamps
    end
  end
end
