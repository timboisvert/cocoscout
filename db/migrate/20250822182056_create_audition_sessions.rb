# frozen_string_literal: true

class CreateAuditionSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :audition_sessions do |t|
      t.references :call_to_audition, null: false, foreign_key: true
      t.datetime :date_and_time

      t.timestamps
    end
  end
end
