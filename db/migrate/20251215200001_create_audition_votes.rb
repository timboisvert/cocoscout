# frozen_string_literal: true

class CreateAuditionVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :audition_votes do |t|
      t.references :audition, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :vote, null: false, default: 0
      t.text :comment

      t.timestamps
    end

    add_index :audition_votes, [ :audition_id, :user_id ], unique: true, name: 'index_audition_votes_unique'
  end
end
