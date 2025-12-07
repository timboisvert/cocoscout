# frozen_string_literal: true

class CreateProductions < ActiveRecord::Migration[8.0]
  def change
    create_table :productions do |t|
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end
