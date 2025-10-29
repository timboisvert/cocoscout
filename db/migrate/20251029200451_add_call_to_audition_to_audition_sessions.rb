class AddCallToAuditionToAuditionSessions < ActiveRecord::Migration[8.1]
  def change
    add_reference :audition_sessions, :call_to_audition, null: true, foreign_key: true
  end
end
