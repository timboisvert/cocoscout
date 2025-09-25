class ChangeAuditionSessionAuditionRelationship < ActiveRecord::Migration[7.0]
  def change
    # Remove join table if it exists
    if table_exists?(:audition_sessions_auditions)
      drop_table :audition_sessions_auditions
    end
    # Add audition_session_id to auditions
    add_reference :auditions, :audition_session, foreign_key: true
  end
end
