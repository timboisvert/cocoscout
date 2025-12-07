# frozen_string_literal: true

class DropCallToAuditionQuestions < ActiveRecord::Migration[8.0]
  def change
    drop_table :call_to_audition_questions
  end
end
