# frozen_string_literal: true

class CreateAuditionSessionsAuditionsJoinTable < ActiveRecord::Migration[8.0]
  def change
    create_table :audition_sessions_auditions, id: false do |t|
      t.references :audition_session, null: false, foreign_key: true
      t.references :audition, null: false, foreign_key: true
    end

    add_index :audition_sessions_auditions, %i[audition_session_id audition_id]
    add_index :audition_sessions_auditions, %i[audition_id audition_session_id]
  end
end
