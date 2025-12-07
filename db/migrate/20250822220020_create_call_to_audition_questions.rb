# frozen_string_literal: true

class CreateCallToAuditionQuestions < ActiveRecord::Migration[8.0]
  def change
    create_table :call_to_audition_questions do |t|
      t.references :call_to_audition, null: false, foreign_key: true
      t.string :key
      t.string :text
      t.string :type

      t.timestamps
    end
  end
end
