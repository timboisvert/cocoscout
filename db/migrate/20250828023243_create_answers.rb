# frozen_string_literal: true

class CreateAnswers < ActiveRecord::Migration[8.0]
  def change
    create_table :answers do |t|
      t.references :question, null: false, foreign_key: true
      t.references :audition_request, null: false, foreign_key: true
      t.string :value

      t.timestamps
    end
  end
end
