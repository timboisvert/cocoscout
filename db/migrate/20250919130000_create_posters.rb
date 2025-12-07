# frozen_string_literal: true

class CreatePosters < ActiveRecord::Migration[8.0]
  def change
    create_table :posters do |t|
      t.string :name
      t.references :production, null: false, foreign_key: true
      t.timestamps
    end
  end
end
