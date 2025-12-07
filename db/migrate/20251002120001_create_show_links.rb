# frozen_string_literal: true

class CreateShowLinks < ActiveRecord::Migration[7.0]
  def change
    create_table :show_links do |t|
      t.references :show, null: false, foreign_key: true
      t.string :url, null: false
      t.timestamps
    end
  end
end
