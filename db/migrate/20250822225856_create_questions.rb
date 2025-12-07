# frozen_string_literal: true

class CreateQuestions < ActiveRecord::Migration[8.0]
  def change
    create_table :questions do |t|
      t.string :key
      t.string :text
      t.string :type
      t.references :questionable, polymorphic: true, null: false

      t.timestamps
    end
  end
end
