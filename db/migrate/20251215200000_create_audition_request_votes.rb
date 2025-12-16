# frozen_string_literal: true

class CreateAuditionRequestVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :audition_request_votes do |t|
      t.references :audition_request, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :vote, null: false, default: 0
      t.text :comment

      t.timestamps
    end

    add_index :audition_request_votes, [ :audition_request_id, :user_id ], unique: true, name: 'index_audition_request_votes_unique'
  end
end
