# frozen_string_literal: true

class CreateCallToAuditions < ActiveRecord::Migration[8.0]
  def change
    create_table :call_to_auditions do |t|
      t.references :production, null: false, foreign_key: true
      t.datetime :opens_at
      t.datetime :closes_at

      t.timestamps
    end
  end
end
