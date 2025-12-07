# frozen_string_literal: true

class CreateAuditionRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :audition_requests do |t|
      t.references :call_to_audition, null: false, foreign_key: true
      t.references :person, null: false, foreign_key: true

      t.timestamps
    end
  end
end
