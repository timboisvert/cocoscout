# frozen_string_literal: true

class CreateAuditionSessionsAgain < ActiveRecord::Migration[8.0]
  def change
    create_table :audition_sessions do |t|
      t.references :production, null: false, foreign_key: true
      t.datetime :start_at
      t.datetime :end_at
      t.integer :maximum_auditionees

      t.timestamps
    end
  end
end
