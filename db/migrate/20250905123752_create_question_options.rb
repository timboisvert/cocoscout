# frozen_string_literal: true

class CreateQuestionOptions < ActiveRecord::Migration[8.0]
  def change
    create_table :question_options do |t|
      t.references :question, null: false, foreign_key: true
      t.string :text

      t.timestamps
    end
  end
end
