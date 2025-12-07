# frozen_string_literal: true

class ChangeAuditionSessionAuditionRelationship < ActiveRecord::Migration[7.0]
  def change
    # Remove join table if it exists
    drop_table :audition_sessions_auditions if table_exists?(:audition_sessions_auditions)
    # Add audition_session_id to auditions
    add_reference :auditions, :audition_session, foreign_key: true
  end
end
